@echo off
REM Send a live command to the deployed Fly dedicated server.
REM Examples:
REM   Scripts\server_command.bat bots off
REM   Scripts\server_command.bat bot_count 4
REM   Scripts\server_command.bat bot_difficulty Hard

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
    exit /b 1
)

SET SERVER_COMMAND=%*
echo Sending to %APP%: %SERVER_COMMAND%
fly ssh console --app %APP% --command "sh -lc 'echo %SERVER_COMMAND% >> %COMMAND_FILE%'"
IF ERRORLEVEL 1 (
    echo ERROR: failed to send command. Check fly auth and app status.
    exit /b 1
)

echo Command queued. Run  fly logs --app %APP%  to see the server response.
