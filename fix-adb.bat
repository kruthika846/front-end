@echo off
REM One-click fix for "adb: device unauthorized" on the emulator.
REM Run this, then try "flutter run" again.
set ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe
"%ADB%" kill-server
timeout /t 2 /nobreak >nul
"%ADB%" start-server
"%ADB%" devices
pause
