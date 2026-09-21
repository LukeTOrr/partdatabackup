@echo off
REM Task Scheduler entry point. Logs to data\run.log (gitignored).
REM Scheduler settings: Start in = this folder. Run whether user is logged on or not
REM only works for headless jobs; visible-browser jobs need "Run only when logged on".
cd /d "%~dp0"
echo ================ %date% %time% ================ >> data\run.log
node launch.js >> data\run.log 2>&1
echo Exit code: %errorlevel% >> data\run.log
