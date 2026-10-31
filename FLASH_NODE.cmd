@echo off
if "%~1"=="" goto usage
if "%~2"=="" goto usage
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Flash-Node.ps1" -NodeId %1 -Port %2
exit /b %errorlevel%
:usage
echo Usage: FLASH_NODE.cmd NODE_ID COM_PORT
echo Example: FLASH_NODE.cmd 0 COM3
exit /b 1
