@echo off
setlocal
set "DIR=%~dp0"
node "%DIR%shim.mjs" %*
