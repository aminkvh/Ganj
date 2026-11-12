"""Regenerate the reading parity fixtures from the Python reading front-end and the voice's G2P.

    python record_units.py <ganj_voice_repo> <g2p_dir> test/fixtures/voice/reading_units.json \
        test/fixtures/voice/reading_units_nometre.json

For every unit of each fixture (same key, lines, kind, metre) runs ganj-reading's `G2P.phonemize_unit` with the shipped
lexicon and the torch model in `<g2p_dir>`, recording every model call it makes (`top1`: the beam-5 output of
`model([text])`; `nbest`: `model.nbest(text, n)`), then the reading (`ganj_corpus.pauses.reading_label`, pauses on,
va off) and the target (`ganj_voice.glue.lead_pause(glue_vav(reading))`). The fixtures are rewritten in place in the
shape `test/features/voice/reading_test.dart` replays: `{"units": [{key, lines, kind, metre, calls, label, error,
reading, target}]}`, `indent=0`, UTF-8 unescaped.

The first fixture also gets one unit per line that the tests added in Ganj voice 89d4add (`tests/test_g2p.py`) put
through `phonemize_line` (keys `t89d4add-<n>`, with that test's metre), recorded with the real model, so each 1.2.0
rule is exercised.

The model is loaded as `export_g2p.py` loads it (eager attention, fp32), so the recorded calls are also what the
app's ONNX files give (`test/features/voice/g2p_onnx_test.dart`). No packages need installing: the repo's
ganj-reading, ganj-corpus and ganj-voice sources are put on the path. Tested with torch 2.15.0, transformers 5.22.2.
"""
import argparse
import json
import sys
from pathlib import Path

HAZAJ = "مفاعیلن مفاعیلن فعولن (هزج مسدس محذوف یا وزن دوبیتی)"
MOJTASS = "مفاعلن فعلاتن مفاعلن فعلن (مجتث مثمن مخبون محذوف)"

# The phonemize_line inputs of the tests added in 89d4add, in file order, each once (line, metre).
NEW_TEST_LINES = [
    ("ببد شاه", None),
    ("زبانی‌است", None),
    ("تسبیح‌خوانی‌است", None),
    ("نی‌است", None),
    ("کی‌است", None),
    ("که هر خاری به تسبیحش زبانی‌است", HAZAJ),
    ("زبانی‌است به مرا که می زرا به کما", MOJTASS),
    ("جهان چه مُحدَث", None),
    ("جهان چه محدث", None),
    ("به خواب، دو چشم", None),
    ("نوشت این مرد: آزادی", None),
    ("حیف! اُستاد", None),
    ("کار ، این کار", None),
    ("خواب،دو چشم", None),
    ("ماه روزه", None),
    ("گفت !هر کس", None),
    ("دلِ، من", None),
    ("تا کی ز قدیم و مُحدَث، اومیدم و بیم", None),
    ("فروزنده اخگر چون انگِشت کرد", None),
    ("گُرسَنه خفتَد", None),
    ("خَطُّ و خال", None),
    ("گُلَ ازْ دست", None),
]


class Recorder:
    """Wraps ganj-reading's model and records each call as the fixtures store it."""

    def __init__(self, inner):
        self.inner = inner
        self.calls = []

    def __call__(self, texts):
        out = self.inner(texts)
        self.calls += [{"call": "top1", "input": t, "out": [o]} for t, o in zip(texts, out)]
        return out

    def nbest(self, text, n):
        out = self.inner.nbest(text, n)
        self.calls.append({"call": "nbest", "input": text, "n": n, "out": out})
        return out


def front_end(repo: Path, g2p_dir: Path):
    for pkg in ("ganj-reading", "ganj-corpus", "ganj-voice"):
        sys.path.insert(0, str(repo / "packages" / pkg))
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from export_g2p import check_interface, load
    from transformers import AutoTokenizer
    from ganj_reading import g2p as G

    check_interface(g2p_dir)
    hf = G._HFModel.__new__(G._HFModel)
    hf.tok, hf.model, hf.device = AutoTokenizer.from_pretrained(str(g2p_dir)), load(g2p_dir), "cpu"
    g = G.G2P.__new__(G.G2P)
    g.model = Recorder(hf)
    g.lexicon = G.load_lexicon(Path(G.__file__).parent / "lexicon.json")
    g.log_path = None
    g.mismatches = 0
    return g


def record(g, unit: dict) -> dict:
    from ganj_corpus.pauses import reading_label
    from ganj_reading.g2p import PhonemizeError
    from ganj_voice.glue import glue_vav, lead_pause

    lines, kind, metre = unit["lines"], unit["kind"], unit["metre"]
    g.model.calls = []
    label = reading = target = error = None
    try:
        label = g.phonemize_unit(lines, kind, metre)
        reading = reading_label(label, lines, prose=kind == "prose", pauses=True, va=False)
        target = lead_pause(glue_vav(reading))
    except PhonemizeError as e:
        error = str(e)
    return {"key": unit["key"], "lines": lines, "kind": kind, "metre": metre, "calls": g.model.calls,
            "label": label, "error": error, "reading": reading, "target": target}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("repo", type=Path, help="Ganj voice checkout (packages/ganj-reading, ganj-corpus, ganj-voice)")
    ap.add_argument("g2p_dir", type=Path, help="the voice's HF g2p/ folder")
    ap.add_argument("fixtures", type=Path, nargs="+", help="reading_units*.json; the first gets the new test lines")
    a = ap.parse_args()
    g = front_end(a.repo, a.g2p_dir)
    for fi, path in enumerate(a.fixtures):
        old = json.loads(path.read_text(encoding="utf-8"))["units"]
        units = [{k: u[k] for k in ("key", "lines", "kind", "metre")} for u in old
                 if not u["key"].startswith("t89d4add-")]
        if fi == 0:
            units += [{"key": f"t89d4add-{n}", "lines": [line], "kind": "verse", "metre": metre}
                      for n, (line, metre) in enumerate(NEW_TEST_LINES)]
        out = []
        for n, u in enumerate(units):
            out.append(record(g, u))
            if n % 50 == 0:
                print(f"{path.name}: {n}/{len(units)}", flush=True)
        path.write_text(json.dumps({"units": out}, ensure_ascii=False, indent=0), encoding="utf-8")
        print(f"{path.name}: {len(out)} units, {sum(len(u['calls']) for u in out)} calls, "
              f"{sum(1 for u in out if u['error'])} errors", flush=True)


if __name__ == "__main__":
    main()
