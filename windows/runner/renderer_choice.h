#ifndef RUNNER_RENDERER_CHOICE_H_
#define RUNNER_RENDERER_CHOICE_H_

#include <string>
#include <vector>

// Start-up diagnostics and renderer/GPU choice for the Windows runner. Everything is
// appended to %TEMP%\ganj.log, so a computer that shows an empty window can tell us how far
// Ganj got and on what hardware (the same file the Dart side logs its steps to).

// Appends one line to %TEMP%\ganj.log (never fails the app).
void GanjLog(const std::string& line);

// Logs the Windows version, which files sit next to the exe, every graphics adapter with its
// driver version and Direct3D 11 level, and whether the WARP software renderer works.
void LogEnvironment();

// Whether to draw with Impeller (Flutter's newer renderer) or Skia.
//
// Ganj uses Skia on Windows by default: Impeller depends on a modern, well-behaved GPU driver and
// shows a blank white window on e.g. Intel HD Graphics 3000 (2011 laptops, Direct3D 10.1 on
// Windows 10). Skia works across old and cheap hardware and falls back to software rendering.
//
// `--renderer=impeller` (or `--renderer=skia`) on the command line overrides the default.
bool ShouldUseImpeller(const std::vector<std::string>& args);

// Which GPU Flutter should prefer: 1 = low power (the integrated chip), 2 = high performance.
// Low power is the default: Ganj is text, the integrated chip is plenty, it saves battery,
// and on an Optimus laptop (Intel + NVIDIA, 2016 drivers) rendering on the NVIDIA chip and
// copying frames across to the Intel-driven screen produced a white window — with the
// integrated chip it works. `--gpu=high` overrides.
int GpuPreferenceFromArgs(const std::vector<std::string>& args);

// Windows' own per-app graphics choice (Settings > System > Display > Graphics settings):
// registers this exe as "Power saving" when the user has made no choice yet, because the
// NVIDIA switching layer honours that setting where Flutter's own preference may be ignored.
// Returns true when the value was just written — it only applies to processes started
// afterwards, so the caller relaunches once.
bool EnsureWindowsGpuPreferencePowerSaving();

// Starts this exe again with the same arguments plus `--relaunched` (never loops).
bool RelaunchOnce(const std::vector<std::string>& args);

// `--diag`: log the environment and exit without opening a window.
bool DiagOnly(const std::vector<std::string>& args);

#endif  // RUNNER_RENDERER_CHOICE_H_
