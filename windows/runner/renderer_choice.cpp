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

std::string Hex(unsigned v) {
  char buf[16] = {0};
  std::snprintf(buf, sizeof(buf), "0x%x", v);
  return buf;
}

// Direct3D 11 feature level reachable with [driver] on [adapter] (0 when a device can't be made).
D3D_FEATURE_LEVEL CreateLevel(IDXGIAdapter* adapter, D3D_DRIVER_TYPE driver) {
  const D3D_FEATURE_LEVEL levels[] = {
      D3D_FEATURE_LEVEL_11_1, D3D_FEATURE_LEVEL_11_0, D3D_FEATURE_LEVEL_10_1,
      D3D_FEATURE_LEVEL_10_0, D3D_FEATURE_LEVEL_9_3,  D3D_FEATURE_LEVEL_9_2,
      D3D_FEATURE_LEVEL_9_1,
  };
  D3D_FEATURE_LEVEL got = static_cast<D3D_FEATURE_LEVEL>(0);
  HRESULT hr = ::D3D11CreateDevice(adapter, driver, nullptr, 0, levels, ARRAYSIZE(levels),
                                   D3D11_SDK_VERSION, nullptr, &got, nullptr);
  if (hr == E_INVALIDARG) {
    // Runtimes without 11_1 reject the whole list; try again without it.
    hr = ::D3D11CreateDevice(adapter, driver, nullptr, 0, levels + 1, ARRAYSIZE(levels) - 1,
                             D3D11_SDK_VERSION, nullptr, &got, nullptr);
  }
  return SUCCEEDED(hr) ? got : static_cast<D3D_FEATURE_LEVEL>(0);
}

D3D_FEATURE_LEVEL MaxFeatureLevel() { return CreateLevel(nullptr, D3D_DRIVER_TYPE_HARDWARE); }

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

bool HasArg(const std::vector<std::string>& args, const char* flag) {
  for (const auto& a : args) {
    if (a == flag) {
      return true;
    }
  }
  return false;
}

std::wstring ExeDir() {
  wchar_t path[MAX_PATH] = {0};
  const DWORD n = ::GetModuleFileNameW(nullptr, path, MAX_PATH);
  std::wstring p(path, n);
  const size_t slash = p.find_last_of(L'\\');
  return slash == std::wstring::npos ? L"." : p.substr(0, slash);
}

bool FileExists(const std::wstring& path) {
  const DWORD a = ::GetFileAttributesW(path.c_str());
  return a != INVALID_FILE_ATTRIBUTES && !(a & FILE_ATTRIBUTE_DIRECTORY);
}

void LogWindowsVersion() {
  typedef LONG(WINAPI * RtlGetVersionFn)(PRTL_OSVERSIONINFOW);
  RTL_OSVERSIONINFOW v = {};
  v.dwOSVersionInfoSize = sizeof(v);
  if (HMODULE ntdll = ::GetModuleHandleW(L"ntdll.dll")) {
    if (auto fn = reinterpret_cast<RtlGetVersionFn>(::GetProcAddress(ntdll, "RtlGetVersion"))) {
      fn(&v);
    }
  }
  char buf[96] = {0};
  std::snprintf(buf, sizeof(buf), "windows %lu.%lu build %lu", v.dwMajorVersion, v.dwMinorVersion,
                v.dwBuildNumber);
  GanjLog(buf);
}

void LogFiles() {
  const std::wstring dir = ExeDir();
  GanjLog("exe folder: " + Utf8FromUtf16(dir.c_str()));
  if (dir.find(L".zip") != std::wstring::npos || dir.find(L"\\Temp\\") != std::wstring::npos ||
      dir.find(L"\\Temp1_") != std::wstring::npos) {
    GanjLog("WARNING: running from a temporary folder - was the zip extracted first?");
  }
  const wchar_t* files[] = {L"flutter_windows.dll", L"data\\icudtl.dat", L"data\\app.so",
                            L"data\\flutter_assets\\AssetManifest.bin", L"msvcp140.dll",
                            L"vcruntime140.dll", L"vcruntime140_1.dll"};
  std::string missing;
  for (const wchar_t* f : files) {
    if (!FileExists(dir + L"\\" + f)) {
      missing += Utf8FromUtf16(f) + " ";
    }
  }
  GanjLog(missing.empty() ? "files: all present" : "files MISSING: " + missing);
}

void LogAdapters() {
  IDXGIFactory1* factory = nullptr;
  if (FAILED(::CreateDXGIFactory1(__uuidof(IDXGIFactory1), reinterpret_cast<void**>(&factory)))) {
    GanjLog("dxgi: factory could not be created");
    return;
  }
  for (UINT i = 0;; i++) {
    IDXGIAdapter1* adapter = nullptr;
    if (factory->EnumAdapters1(i, &adapter) != S_OK) {
      break;
    }
    DXGI_ADAPTER_DESC1 desc = {};
    adapter->GetDesc1(&desc);
    LARGE_INTEGER umd = {};
    std::string driver = "driver ?";
    if (SUCCEEDED(adapter->CheckInterfaceSupport(__uuidof(IDXGIDevice), &umd))) {
      char buf[64] = {0};
      std::snprintf(buf, sizeof(buf), "driver %u.%u.%u.%u", HIWORD(umd.HighPart),
                    LOWORD(umd.HighPart), HIWORD(umd.LowPart), LOWORD(umd.LowPart));
      driver = buf;
    }
    const bool software = (desc.Flags & DXGI_ADAPTER_FLAG_SOFTWARE) != 0;
    const D3D_FEATURE_LEVEL level =
        software ? static_cast<D3D_FEATURE_LEVEL>(0) : CreateLevel(adapter, D3D_DRIVER_TYPE_UNKNOWN);
    char vram[32] = {0};
    std::snprintf(vram, sizeof(vram), "%llu MB", static_cast<unsigned long long>(desc.DedicatedVideoMemory >> 20));
    GanjLog("adapter " + std::to_string(i) + ": " + Utf8FromUtf16(desc.Description) + " (vendor " +
            Hex(desc.VendorId) + ", device " + Hex(desc.DeviceId) + ", " + vram + ", " + driver +
            (software ? ", software" : ", Direct3D 11 level " + Hex(level)) + ")");
    adapter->Release();
  }
  factory->Release();
  GanjLog("warp (software Direct3D) level " + Hex(CreateLevel(nullptr, D3D_DRIVER_TYPE_WARP)));
}

}  // namespace

void LogEnvironment() {
  LogWindowsVersion();
  LogFiles();
  LogAdapters();
}

bool ShouldUseImpeller(const std::vector<std::string>& args) {
  if (HasArg(args, "--renderer=skia")) {
    GanjLog("renderer: Skia (--renderer=skia)");
    return false;
  }
  if (HasArg(args, "--renderer=impeller")) {
    GanjLog("renderer: Impeller (--renderer=impeller)");
    return true;
  }
  // Skia by default: it has drawn Flutter on Windows for years and copes with old, cheap or
  // badly-driven GPUs (and falls back to software rendering), where Impeller can show a white
  // window. Ganj is text and simple shapes, so Skia costs nothing visible.
  GanjLog("gpu: " + AdapterName() + ", Direct3D feature level " + Hex(MaxFeatureLevel()) +
          " -> renderer: Skia (default)");
  return false;
}

int GpuPreferenceFromArgs(const std::vector<std::string>& args) {
  if (HasArg(args, "--gpu=low")) {
    GanjLog("gpu preference: low power (--gpu=low)");
    return 1;
  }
  if (HasArg(args, "--gpu=high")) {
    GanjLog("gpu preference: high performance (--gpu=high)");
    return 2;
  }
  return 0;
}

bool DiagOnly(const std::vector<std::string>& args) { return HasArg(args, "--diag"); }
