@echo off
setlocal EnableExtensions
cd /d "%~dp0"
title Ragnarok Installer Manager v6.0

net session >nul 2>&1
if errorlevel 1 (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-Manager.ps1"
set "EXITCODE=%errorlevel%"

if not "%EXITCODE%"=="0" (
    echo.
    echo [ERROR] Installer exited with code: %EXITCODE%
    pause
)

exit /b %EXITCODE%
