@echo off
REM Double-click me. Sets the date when every Cloud Scheduler job gets
REM snapshotted, paused and deleted. Always noon Pacific on that date.
title Set schedule-removal date
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\set-removal-date.ps1"
set RC=%errorlevel%
echo.
if %RC%==0 (echo [done] Finished OK.) else (echo [done] Finished with errors - exit code %RC%.)
echo.
echo This window stays open on purpose. Close it when you have read the result.
pause
