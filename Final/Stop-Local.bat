@echo off
setlocal EnableExtensions
cd /d "%~dp0"

echo =====================================================
echo Pharmacy Management System - Stop Local Services
echo =====================================================
echo.
echo Stopping the service windows started by Run-Local.bat...

rem Close the named command windows and their child processes.
for %%W in ("Auth Service - 5001" "Inventory Service - 5002" "Order Service - 5003" "Payment Service - 5004" "Sales Report Service - 5005" "Notification Service - 5006" "YARP API Gateway - 5000") do (
    taskkill /F /T /FI "WINDOWTITLE eq %%~W" >nul 2>&1
)

echo Checking ports 5000 through 5006 for any remaining listeners...

rem Fallback: stop any process still listening on one of this project's ports.
rem The /T switch also stops child processes where possible.
for %%P in (5000 5001 5002 5003 5004 5005 5006) do (
    for /f "tokens=5" %%I in ('netstat -ano -p tcp ^| findstr /R /C:":%%P .*LISTENING"') do (
        if not "%%I"=="0" (
            echo Stopping process %%I on port %%P...
            taskkill /PID %%I /T /F >nul 2>&1
        )
    )
)

timeout /t 2 /nobreak >nul

echo.
echo Remaining listeners on ports 5000-5006:
set "FOUND=0"
for %%P in (5000 5001 5002 5003 5004 5005 5006) do (
    for /f "tokens=5" %%I in ('netstat -ano -p tcp ^| findstr /R /C:":%%P .*LISTENING"') do (
        echo WARNING: Port %%P is still listening under PID %%I.
        set "FOUND=1"
    )
)
if "%FOUND%"=="0" echo All Pharmacy Management System service ports are stopped.

echo.
echo Note: This script does not stop SQL Server LocalDB itself.
echo =====================================================
pause
endlocal
