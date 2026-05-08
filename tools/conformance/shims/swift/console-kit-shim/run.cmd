@echo off
rem Wrapper that resolves the platform-specific .build\<triple>\release\ path.
setlocal enabledelayedexpansion
set "DIR=%~dp0"
cd /d "%DIR%"
for /f "delims=" %%i in ('swift build -c release --show-bin-path 2^>nul') do set "BIN_DIR=%%i"
"%BIN_DIR%\ConsoleKitShim.exe" %*
