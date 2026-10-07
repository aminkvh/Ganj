#ifndef RUNNER_RENDERER_CHOICE_H_
#define RUNNER_RENDERER_CHOICE_H_

#include <string>
#include <vector>

// Whether to draw with Impeller (Flutter's newer renderer) or Skia.
//
// Ganj uses Skia on Windows by default: Impeller depends on a modern, well-behaved GPU driver and
// shows a blank white window on e.g. Intel HD Graphics 3000 (2011 laptops, Direct3D 10.1 on
// Windows 10). Skia works across old and cheap hardware and falls back to software rendering.
//
// `--renderer=impeller` (or `--renderer=skia`) on the command line overrides the default.
// The GPU and the decision are appended to %TEMP%\ganj.log.
bool ShouldUseImpeller(const std::vector<std::string>& args);

// Appends one line to %TEMP%\ganj.log (start-up diagnostics; never fails the app).
void GanjLog(const std::string& line);

#endif  // RUNNER_RENDERER_CHOICE_H_
