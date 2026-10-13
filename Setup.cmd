@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\bootstrap.ps1"
if errorlevel 1 goto failed
python "%~dp0tools\test.py"
if errorlevel 1 goto failed
python "%~dp0tools\build.py"
if errorlevel 1 goto failed
echo Setup complete. Run Start.cmd for a trial, or Rollback.cmd to stop it.
exit /b 0
:failed
echo Setup failed. Nothing should be enabled until setup completes.
pause
exit /b 1
