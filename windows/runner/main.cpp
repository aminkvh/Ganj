#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "renderer_choice.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  GanjLog("start");
  LogEnvironment();
  if (DiagOnly(command_line_arguments)) {
    // `ganj.exe --diag`: the facts above are all we wanted; no window.
    GanjLog("diag done");
    ::CoUninitialize();
    return EXIT_SUCCESS;
  }
  // Older GPUs (e.g. Intel HD Graphics 3000) show a white window with Impeller: use Skia there.
  project.set_impeller_switch(ShouldUseImpeller(command_line_arguments)
                                  ? flutter::ImpellerSwitch::Enabled
                                  : flutter::ImpellerSwitch::Disabled);
  // The integrated graphics chip by default (see renderer_choice.h); `--gpu=high` overrides.
  const int gpu = GpuPreferenceFromArgs(command_line_arguments);
  project.set_gpu_preference(gpu == 2 ? flutter::GpuPreference::HighPerformancePreference
                                      : flutter::GpuPreference::LowPowerPreference);
  // Also tell Windows itself (per-app graphics setting), once, and start again so it applies
  // to this very first run too.
  if (gpu == 1 && EnsureWindowsGpuPreferencePowerSaving() && RelaunchOnce(command_line_arguments)) {
    ::CoUninitialize();
    return EXIT_SUCCESS;
  }

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  // Window title: Persian name and Latin name (escaped so the source stays ASCII for MSVC).
  if (!window.Create(L"\x06AF\x0646\x062C \x2014 Ganj", origin, size)) {
    GanjLog("window could not be created");
    return EXIT_FAILURE;
  }
  GanjLog("window created");
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
