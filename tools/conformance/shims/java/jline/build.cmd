@echo off
rem Build script for the JLine shim:
rem   - download jline-X.jar to libs\ (one-time, idempotent)
rem   - javac the Java source
setlocal enabledelayedexpansion
set "DIR=%~dp0"
cd /d "%DIR%"

if not defined JLINE_VERSION set "JLINE_VERSION=3.30.4"
set "JLINE_JAR=libs\jline.jar"
set "JLINE_URL=https://repo1.maven.org/maven2/org/jline/jline/%JLINE_VERSION%/jline-%JLINE_VERSION%.jar"

if not exist libs mkdir libs
if not exist build mkdir build

if not exist "%JLINE_JAR%" (
    echo Downloading JLine %JLINE_VERSION%... 1>&2
    curl -fsSL -o "%JLINE_JAR%" "%JLINE_URL%"
    if errorlevel 1 (
        echo Failed to download JLine 1>&2
        exit /b 1
    )
)

rem --release 17 keeps us inside JLine's compiled bytecode floor while
rem tolerating Java 25 host (host warns about restricted API but still works).
javac --release 17 -cp "%JLINE_JAR%" -d build src\JlineShim.java
if errorlevel 1 exit /b 1
echo JLine shim compiled to build\JlineShim.class 1>&2
