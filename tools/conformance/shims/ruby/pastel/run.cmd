@echo off
setlocal
set "DIR=%~dp0"
cd /d "%DIR%"
set "BUNDLE_PATH=vendor/bundle"
bundle exec ruby shim.rb %*
