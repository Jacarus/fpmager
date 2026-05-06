@echo off
REM Send a live command to the deployed Fly dedicated server.
REM Examples:
REM   Scripts\server_command.bat bots off
REM   Scripts\server_command.bat bot_count 4
REM   Scripts\server_command.bat bot_difficulty Hard
REM   Scripts\server_command.bat boss status
REM   Scripts\server_command.bat boss spawn health=2400 name=Aether_Colossus
REM   Scripts\server_command.bat boss replace health=4000 respawn=on
REM   Scripts\server_command.bat boss despawn 0

SET APP=fp-mager
SET COMMAND_FILE=/tmp/fp-mager-commands.txt

IF "%~1"=="" (
    echo Usage: %~nx0 ^<server command^>
    echo.
    echo Commands:
    echo   status
    echo   bots on
    echo   bots off
    echo   bots ^<0-12^>
    echo   bot_count ^<0-12^>
    echo   bot_difficulty ^<Easy^|Medium^|Hard^>
    echo   boss status
    echo   boss spawn health=2400 name=Aether_Colossus scale=1.2 cooldown=0.85 speed=1.1 respawn=off
    echo   boss spawn health=2400 replace=on
    echo   boss replace health=4000 respawn=on
    echo   boss despawn 0
    exit /b 1
)

SET SERVER_COMMAND=%*
echo Sending to %APP%: %SERVER_COMMAND%
SET SSH_ERROR_LOG=%TEMP%\fp-mager-fly-ssh-error.log
fly ssh console --app %APP% --command "sh -lc 'echo %SERVER_COMMAND% >> %COMMAND_FILE%'" >nul 2>"%SSH_ERROR_LOG%"
IF NOT ERRORLEVEL 1 (
    echo Command queued. Run  fly logs --app %APP% --no-tail  to see the server response.
    exit /b 0
)

findstr /C:"The handle is invalid" "%SSH_ERROR_LOG%" >nul 2>nul
IF NOT ERRORLEVEL 1 (
    echo Command queued. Fly reported a Windows terminal-handle warning after sending.
    echo Run  fly logs --app %APP% --no-tail  to see the server response.
    exit /b 0
)

echo Primary fly ssh console send failed. Trying machine exec fallback...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0server_command.ps1" %*
IF ERRORLEVEL 1 (
    echo ERROR: failed to send command. Check fly auth and app status.
    exit /b 1
)

exit /b 0
