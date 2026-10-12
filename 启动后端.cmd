@echo off
if exist "%~dp0local-ai-key.cmd" call "%~dp0local-ai-key.cmd"
cd /d "%~dp0backend"
if not defined TESSERACT_EXE if exist "C:\Program Files\Tesseract-OCR\tesseract.exe" set "TESSERACT_EXE=C:\Program Files\Tesseract-OCR\tesseract.exe"
echo Starting invoice API at http://127.0.0.1:8080
echo First run may download Maven dependencies.
call mvn.cmd spring-boot:run
pause
