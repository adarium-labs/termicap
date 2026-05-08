@echo off
rem Build script: cabal build + install binary into bin\ for a stable manifest path.
setlocal
set "DIR=%~dp0"
cd /d "%DIR%"

if not exist bin mkdir bin

cabal build
if errorlevel 1 exit /b 1
cabal install --installdir=bin --install-method=copy --overwrite-policy=always exe:ansi-terminal-shim
if errorlevel 1 exit /b 1
echo ansi-terminal-shim built at bin\ansi-terminal-shim 1>&2
