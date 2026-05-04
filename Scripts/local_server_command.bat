@echo off
REM Append a command to the local dedicated-server command file.

setlocal
set "PROJECT_ROOT=%~dp0.."
if "%SERVER_COMMAND_FILE%"=="" set "SERVER_COMMAND_FILE=%PROJECT_ROOT%\local-server-commands.txt"

if "%~1"=="" (
    echo Usage: %~nx0 ^<server command^>
    echo.
    echo Examples:
    echo   %~nx0 status
    echo   %~nx0 bots on
    echo   %~nx0 boss status
    echo   %~nx0 boss replace health=2400 respawn=on
    exit /b 1
)

if not exist "%SERVER_COMMAND_FILE%" type nul > "%SERVER_COMMAND_FILE%"

echo %*>>"%SERVER_COMMAND_FILE%"
echo Command queued locally: %*
echo Watch the dedicated server window for [ServerCommand] output.
