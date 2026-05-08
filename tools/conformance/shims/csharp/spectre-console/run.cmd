@echo off
setlocal
set "DIR=%~dp0"
dotnet "%DIR%publish\SpectreConsoleShim.dll" %*
