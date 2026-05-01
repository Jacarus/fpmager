@echo off
REM ============================================================
REM  FP Mager — export Linux dedicated server and deploy to fly.io
REM ============================================================
REM
REM Prerequisites:
REM   1. Godot 4.6 installed (update GODOT_EXE path below if needed)
REM   2. Godot Linux export templates installed (Editor -> Export Templates)
REM   3. flyctl installed  https://fly.io/docs/hands-on/install-flyctl/
REM   4. Logged in:  fly auth login
REM   5. App created (first time only):  fly launch --no-deploy
REM   6. Dedicated IPv4 allocated (first time only):
REM        fly ips allocate-v4 --app fp-mager
REM ============================================================

SET GODOT_EXE=C:\Tools\Godot\godot.exe
SET PROJECT_DIR=%~dp0..
SET EXPORT_DIR=%PROJECT_DIR%\build\server

echo [1/3] Exporting Linux dedicated server...
"%GODOT_EXE%" --headless --path "%PROJECT_DIR%" --export-release "Linux Server" "%EXPORT_DIR%\fp-mager.x86_64"
IF ERRORLEVEL 1 (
    echo ERROR: Godot export failed. Check that:
    echo   - GODOT_EXE path is correct
    echo   - Linux export templates are installed
    echo   - export_presets.cfg exists in the project root
    exit /b 1
)

echo [2/3] Building Docker image...
cd /d "%PROJECT_DIR%"
docker build -t fp-mager-server .
IF ERRORLEVEL 1 (
    echo ERROR: Docker build failed.
    exit /b 1
)

echo [3/3] Deploying to fly.io...
fly deploy
IF ERRORLEVEL 1 (
    echo ERROR: fly deploy failed. Run  fly logs  for details.
    exit /b 1
)

echo.
echo Done. Players can connect to your fly.io IPv4 on UDP port 24567.
echo Run  fly ips list --app fp-mager  to find your server address.
