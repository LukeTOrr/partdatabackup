@echo off
REM Double-click me. Re-creates every Cloud Scheduler job from the latest
REM snapshot in GCS, in the state it was in before the teardown.
title Restore all schedules
cd /d "%~dp0"
echo =======================================================
echo  Restore ALL Cloud Scheduler jobs from the last snapshot
echo =======================================================
echo.
set /p OK="Restore now? (y/n): "
if /i not "%OK%"=="y" (echo Cancelled. & echo. & pause & exit /b 0)
echo.
gcloud run jobs execute scheduler-sunset --region=us-central1 --project=celltech-internal-tools --args=restore --wait
set RC=%errorlevel%
echo.
echo --- Schedules now in the project ---
gcloud scheduler jobs list --location=us-central1 --project=celltech-internal-tools --format="table(name.basename(),state,schedule)"
gcloud scheduler jobs list --location=us-east1 --project=celltech-internal-tools --format="table(name.basename(),state,schedule)"
echo.
if %RC%==0 (echo [done] Restore finished OK.) else (echo [done] Restore FAILED - exit code %RC%. Check the execution logs.)
echo.
echo This window stays open on purpose. Close it when you have read the result.
pause
