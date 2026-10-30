@echo off
rem Activation code generator (Windows shortcut)
rem   double-click                 - interactive prompt
rem   gen-code.bat 20 --csv        - batch, prints order_id,code
rem   gen-code.bat --check SRP-... - verify a code

setlocal
cd /d "%~dp0"

set "DART_BIN=dart"
where dart >nul 2>nul
if errorlevel 1 set "DART_BIN=C://Users//lively lampe\.workbuddy-ai\binaries\flutter\flutter\bin\cache\dart-sdk\bin\dart.exe"

if not "%~1"=="" goto :run

echo.
echo   Activation code generator
echo   ----------------------------------------
echo   Enter          - generate 1 code
echo   10             - generate 10 codes
echo   20 --csv       - generate 20 as order_id,code
echo   --check CODE   - verify a code
echo.
set /p ARGS=  args: 
"%DART_BIN%" run tool\license_gen.dart %ARGS%
echo.
pause
goto :eof

:run
"%DART_BIN%" run tool\license_gen.dart %*
