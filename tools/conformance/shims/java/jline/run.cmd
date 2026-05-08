@echo off
rem Run wrapper that invokes the compiled JLine shim.
setlocal
set "DIR=%~dp0"
java --enable-native-access=ALL-UNNAMED -cp "%DIR%build;%DIR%libs\jline.jar" JlineShim %*
