@echo off
rem Wrapper that invokes shim.py inside this shim's own venv.
setlocal
set "DIR=%~dp0"
"%DIR%.venv\Scripts\python.exe" "%DIR%shim.py" %*
