#include "renderer_choice.h"

#include <d3d11.h>
#include <dxgi.h>
#include <windows.h>

#include <cstdio>
#include <ctime>

#include "utils.h"

void GanjLog(const std::string& line) {
  wchar_t dir[MAX_PATH];
  const DWORD n = ::GetTempPathW(MAX_PATH, dir);
  if (n == 0 || n > MAX_PATH - 16) {
    return;
  }
  std::wstring path(dir);
  path += L"ganj.log";
  FILE* f = nullptr;
  if (_wfopen_s(&f, path.c_str(), L"a") != 0 || f == nullptr) {
    return;
  }
  std::time_t now = std::time(nullptr);
  char stamp[32] = {0};
  std::tm local = {};
  if (localtime_s(&local, &now) == 0) {
    std::strftime(stamp, sizeof(stamp), "%Y-%m-%d %H:%M:%S", &local);
  }
  std::fprintf(f, "%s  %s\n", stamp, line.c_str());
  std::fclose(f);
}

namespace {

// The highest Direct3D 11 feature level the default GPU offers (0 if none).
D3D_FEATURE_LEVEL MaxFeatureLevel() {
  const D3D_FEATURE_LEVEL levels[] = {
      D3D_FEATURE_LEVEL_11_1, D3D_FEATURE_LEVEL_11_0, D3D_FEATURE_LEVEL_10_1,
      D3D_FEATURE_LEVEL_10_0, D3D_FEATURE_LEVEL_9_3,  D3D_FEATURE_LEVEL_9_2,
      D3D_FEATURE_LEVEL_9_1,
  };
  D3D_FEATURE_LEVEL got = static_cast<D3D_FEATURE_LEVEL>(0);
  HRESULT hr = ::D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, 0, levels,
                                   ARRAYSIZE(levels), D3D11_SDK_VERSION, nullptr, &got, nullptr);
  if (hr == E_INVALIDARG) {
    // Runtimes without 11_1 reject the whole list; try again without it.
    hr = ::D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, 0, levels + 1,
                             ARRAYSIZE(levels) - 1, D3D11_SDK_VERSION, nullptr, &got, nullptr);
  }
  return SUCCEEDED(hr) ? got : static_cast<D3D_FEATURE_LEVEL>(0);
}

std::string AdapterName() {
  IDXGIFactory1* factory = nullptr;
  if (FAILED(::CreateDXGIFactory1(__uuidof(IDXGIFactory1), reinterpret_cast<void**>(&factory)))) {
    return "unknown";
  }
  std::string name = "unknown";
  IDXGIAdapter1* adapter = nullptr;
  if (SUCCEEDED(factory->EnumAdapters1(0, &adapter))) {
    DXGI_ADAPTER_DESC1 desc = {};
    if (SUCCEEDED(adapter->GetDesc1(&desc))) {
      name = Utf8FromUtf16(desc.Description);
    }
    adapter->Release();
  }
  factory->Release();
  return name;
}

}  // namespace

bool ShouldUseImpeller(const std::vector<std::string>& args) {
  for (const auto& a : args) {
    if (a == "--renderer=skia") {
      GanjLog("renderer: Skia (--renderer=skia)");
      return false;
    }
    if (a == "--renderer=impeller") {
      GanjLog("renderer: Impeller (--renderer=impeller)");
      return true;
    }
  }
  // Skia by default: it has drawn Flutter on Windows for years and copes with old, cheap or
  // badly-driven GPUs (and falls back to software rendering), where Impeller can show a white
  // window. Ganj is text and simple shapes, so Skia costs nothing visible. The GPU is still
  // logged, to help with any report.
  const D3D_FEATURE_LEVEL level = MaxFeatureLevel();
  char hex[16] = {0};
  std::snprintf(hex, sizeof(hex), "0x%x", static_cast<unsigned>(level));
  GanjLog("gpu: " + AdapterName() + ", Direct3D feature level " + hex + " -> renderer: Skia (default)");
  return false;
}
