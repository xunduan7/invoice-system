@echo off
cd /d "%~dp0frontend"
if not exist node_modules (
  echo Installing frontend dependencies...
  call npm.cmd ci
  if errorlevel 1 (
    pause
    exit /b 1
  )
)
echo Opening frontend at http://127.0.0.1:5173
call npm.cmd run dev -- --host 127.0.0.1
pause
