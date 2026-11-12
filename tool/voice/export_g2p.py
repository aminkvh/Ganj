"""Export the voice's G2P (HF `g2p/`, a 2+2-layer ByT5) to the two ONNX files the app runs.

    python export_g2p.py <g2p_dir> <out_dir> [--check reading_units.json ...]

Writes `<out_dir>/g2p_encoder.onnx` and `<out_dir>/g2p_decoder.onnx`, fp32, opset 17, with the graph names
`lib/features/voice/engine/g2p_onnx.dart` feeds:
- encoder: `ids` int64 [1, S] (utf8 byte + 3, no eos) -> `enc` float [1, S, d_model]
- decoder (no cache): `dec_ids` int64 [B, L], `enc` float [B, S, d_model] -> `logp` float [B, vocab], the
  log-softmax of the last position.

Stops if the model's interface is not the one the app expects (vocab 384, d_model 512, eos 1, start 0, bytes + 3).

`--check` feeds every recorded model call in the given fixtures (units[].calls: {call: top1|nbest, input, n}) to torch
`generate` (num_beams 5 for top1; n beams, n returns for nbest; max_length 512, as ganj-reading calls it) and to a
Python copy of the app's beam search over the ONNX files, and reports how many come out identical.
Needs torch, transformers 5, onnx, onnxruntime (CPU is enough). Tested with torch 2.15.0, transformers 5.22.2.
"""
import argparse
import json
import sys
from pathlib import Path

import numpy as np

EXPECT = {"vocab_size": 384, "d_model": 512, "eos_token_id": 1, "decoder_start_token_id": 0, "pad_token_id": 0}
BYTE_OFFSET = 3
OPSET = 17
MAX_LENGTH = 512


def check_interface(g2p_dir: Path):
    cfg = json.loads((g2p_dir / "config.json").read_text(encoding="utf-8"))
    bad = {k: (cfg.get(k), v) for k, v in EXPECT.items() if cfg.get(k) != v}
    if cfg.get("tokenizer_class") != "ByT5Tokenizer":
        bad["tokenizer_class"] = (cfg.get("tokenizer_class"), "ByT5Tokenizer")
    added = json.loads((g2p_dir / "added_tokens.json").read_text(encoding="utf-8")) if (g2p_dir / "added_tokens.json").exists() else {}
    # ByT5: pad 0, eos 1, unk 2, then the 256 bytes (3..258), then the extra ids up to the vocab size.
    if added and min(added.values()) < 256 + BYTE_OFFSET:
        bad["added_tokens"] = (min(added.values()), ">= 259")
    if bad:
        sys.exit(f"interface differs from what g2p_onnx.dart expects (got, want): {bad}")
    return cfg


def load(g2p_dir: Path):
    import torch
    from transformers import T5ForConditionalGeneration
    torch.manual_seed(0)
    model = T5ForConditionalGeneration.from_pretrained(str(g2p_dir), attn_implementation="eager").eval()
    return model.float()


def export(model, out_dir: Path):
    import torch

    class Enc(torch.nn.Module):
        def __init__(self, m):
            super().__init__()
            self.m = m

        def forward(self, ids):
            return self.m.get_encoder()(input_ids=ids).last_hidden_state

    class Dec(torch.nn.Module):
        def __init__(self, m):
            super().__init__()
            self.m = m

        def forward(self, dec_ids, enc):
            # The same forward generate() runs, without the cache: logits of the last position, log-softmax in fp32.
            logits = self.m(encoder_outputs=(enc,), decoder_input_ids=dec_ids, use_cache=False).logits
            return torch.log_softmax(logits[:, -1, :].float(), dim=-1)

    out_dir.mkdir(parents=True, exist_ok=True)
    ids = torch.tensor([[b + BYTE_OFFSET for b in "سلام دنیا".encode()]], dtype=torch.long)
    with torch.no_grad():
        enc = Enc(model)(ids)
        dec_ids = torch.zeros((2, 3), dtype=torch.long)
        enc2 = enc.expand(2, -1, -1).contiguous()
        torch.onnx.export(Enc(model), (ids,), str(out_dir / "g2p_encoder.onnx"), input_names=["ids"],
                          output_names=["enc"], dynamic_axes={"ids": {1: "S"}, "enc": {1: "S"}},
                          opset_version=OPSET, do_constant_folding=True, dynamo=False)
        torch.onnx.export(Dec(model), (dec_ids, enc2), str(out_dir / "g2p_decoder.onnx"),
                          input_names=["dec_ids", "enc"], output_names=["logp"],
                          dynamic_axes={"dec_ids": {0: "B", 1: "L"}, "enc": {0: "B", 1: "S"}, "logp": {0: "B"}},
                          opset_version=OPSET, do_constant_folding=True, dynamo=False)


class OnnxBeam:
    """A Python copy of OnnxG2pModel.generate (g2p_onnx.dart), float32 where the Dart code stores Float32List."""

    NEG = -1.0e9

    def __init__(self, out_dir: Path, threads: int = 4):
        import onnxruntime as ort
        so = ort.SessionOptions()
        so.intra_op_num_threads = threads
        self.enc = ort.InferenceSession(str(out_dir / "g2p_encoder.onnx"), so, providers=["CPUExecutionProvider"])
        self.dec = ort.InferenceSession(str(out_dir / "g2p_decoder.onnx"), so, providers=["CPUExecutionProvider"])

    @staticmethod
    def _topk(x, k):
        return [int(i) for i in np.argsort(-np.asarray(x, dtype=np.float32), kind="stable")[:k]]

    @staticmethod
    def _decode(seq):
        if seq is None:
            return ""
        b = bytes(t - BYTE_OFFSET for t in seq[1:] if BYTE_OFFSET <= t < 256 + BYTE_OFFSET)
        return b.decode("utf-8", errors="replace").replace("�", "").strip()

    def generate(self, text, num_beams, num_return):
        f32 = np.float32
        neg = self.NEG
        ids = np.array([[b + BYTE_OFFSET for b in text.encode("utf-8")]], dtype=np.int64)
        enc = self.enc.run(["enc"], {"ids": ids})[0]
        enc_b = np.repeat(enc, num_beams, axis=0)
        k = 2 * num_beams
        run_seq = [[0] for _ in range(num_beams)]
        run_sc = [neg] * num_beams
        run_sc[0] = 0.0
        fin_seq, fin_sc, fin_done = [None] * num_beams, [neg] * num_beams, [False] * num_beams
        improving, cur = True, 1
        while True:
            dec = np.array(run_seq, dtype=np.int64)
            lp = self.dec.run(["logp"], {"dec_ids": dec, "enc": enc_b})[0]
            v = lp.shape[1]
            acc = (lp.astype(f32) + np.array(run_sc, dtype=f32)[:, None]).reshape(-1)
            top = self._topk(acc, k)
            tlp = [float(acc[i]) for i in top]
            tseq = [run_seq[i // v] + [i % v] for i in top]
            hit = [i % v == 1 or cur + 1 >= MAX_LENGTH for i in top]
            rlp = np.array([tlp[j] + (neg if hit[j] else 0) for j in range(k)], dtype=f32)
            nxt = self._topk(rlp, num_beams)
            new_seq, new_sc = [tseq[j] for j in nxt], [float(rlp[j]) for j in nxt]
            fsc = np.array([(tlp[j] / cur) + (0 if improving else neg) + (0 if hit[j] and j < num_beams else neg)
                            for j in range(k)], dtype=f32)
            m_sc = np.concatenate([np.array(fin_sc, dtype=f32), fsc])
            m_seq = fin_seq + tseq
            m_done = fin_done + [hit[j] and j < num_beams for j in range(k)]
            keep = self._topk(m_sc, num_beams)
            fin_sc, fin_seq, fin_done = [float(m_sc[i]) for i in keep], [m_seq[i] for i in keep], [m_done[i] for i in keep]
            run_seq, run_sc = new_seq, new_sc
            cur += 1
            best_run = float(f32(run_sc[0] / (cur - 1)))
            worst = min(fin_sc)
            improving = improving and any(best_run > (worst if d else neg) for d in fin_done)
            if not improving or all(hit):
                break
        return [self._decode(s) for s in fin_seq[:num_return]]


def recorded_calls(paths):
    calls = []
    for p in paths:
        for u in json.loads(Path(p).read_text(encoding="utf-8"))["units"]:
            cs = u.get("calls") or []
            calls.extend(json.loads(cs) if isinstance(cs, str) else cs)
    return calls


def torch_generate(model, tok, text, num_beams, num_return):
    """The reference: what ganj-reading's _HFModel returns for this call."""
    import torch
    enc = tok([text], return_tensors="pt", add_special_tokens=False)
    with torch.no_grad():
        gen = model.generate(**enc, num_beams=num_beams, num_return_sequences=num_return, max_length=MAX_LENGTH)
    return [o.strip() for o in tok.batch_decode(gen, skip_special_tokens=True)]


def check(model, g2p_dir: Path, out_dir: Path, fixtures, report=None):
    from transformers import AutoTokenizer
    tok = AutoTokenizer.from_pretrained(str(g2p_dir))
    beam = OnnxBeam(out_dir)
    calls = recorded_calls(fixtures)
    same, diffs, rows = 0, [], []
    for c in calls:
        n = 5 if c["call"] == "top1" else int(c["n"])
        r = 1 if c["call"] == "top1" else n
        want = torch_generate(model, tok, c["input"], n, r)
        got = beam.generate(c["input"], n, r)
        rows.append({"call": c["call"], "input": c["input"], "n": c.get("n"), "torch": want, "onnx": got,
                     "recorded_1_0_0": c.get("out")})
        if want == got:
            same += 1
        else:
            diffs.append((c["input"], want[:3], got[:3]))
    if report:
        Path(report).write_text(json.dumps(rows, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"{same}/{len(calls)} identical (torch vs ONNX)")
    for d in diffs[:10]:
        print("DIFF", d)
    return same == len(calls)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("g2p_dir", type=Path)
    ap.add_argument("out_dir", type=Path)
    ap.add_argument("--check", nargs="*", default=[], help="reading_units*.json fixtures whose calls to compare")
    ap.add_argument("--report", help="write every checked call (torch and ONNX outputs) to this JSON file")
    ap.add_argument("--skip-export", action="store_true", help="only run --check on existing files in out_dir")
    a = ap.parse_args()
    check_interface(a.g2p_dir)
    model = load(a.g2p_dir)
    if not a.skip_export:
        export(model, a.out_dir)
        print("exported", *(f"{p.name} {p.stat().st_size}" for p in sorted(a.out_dir.glob("g2p_*.onnx"))))
    if a.check and not check(model, a.g2p_dir, a.out_dir, a.check, a.report):
        sys.exit(1)


if __name__ == "__main__":
    main()
