@echo off
rem Collects everything needed to find out why Ganj does not start on this computer,
rem into one zip file on the Desktop. Nothing personal is gathered: Ganj's own start-up
rem log, DirectX's system report (graphics chip and driver) and the Windows version.
setlocal
set "OUT=%USERPROFILE%\Desktop\ganj-diagnostics"
set "ZIP=%USERPROFILE%\Desktop\ganj-diagnostics.zip"
if exist "%OUT%" rmdir /s /q "%OUT%"
mkdir "%OUT%"

echo [1/4] Ganj's own checks (graphics chip, DirectX levels, files)...
"%~dp0ganj.exe" --diag

echo [2/4] Starting Ganj for 15 seconds so its start-up steps get logged...
start "" "%~dp0ganj.exe"
timeout /t 15 /nobreak >nul
taskkill /im ganj.exe /f >nul 2>nul

echo [3/4] DirectX report (this one takes a minute)...
dxdiag /t "%OUT%\dxdiag.txt"

echo [4/4] Gathering the logs...
copy "%TEMP%\ganj.log" "%OUT%\" >nul 2>nul
copy "%TEMP%\ganj-startup.log" "%OUT%\" >nul 2>nul
ver > "%OUT%\windows-version.txt"
dir "%~dp0" > "%OUT%\ganj-folder.txt"
powershell -NoProfile -Command "Compress-Archive -Path '%OUT%\*' -DestinationPath '%ZIP%' -Force"
rmdir /s /q "%OUT%"

echo.
echo Done. Please send the file  ganj-diagnostics.zip  from your Desktop.
echo.
pause
