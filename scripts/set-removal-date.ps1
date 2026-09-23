# Reschedule the one-shot trigger that tears down every Cloud Scheduler job.
# Driven by set-removal-date.bat — double-click that, don't run this directly.
# Time is always 12:00 PM Pacific; only the date changes.

$ErrorActionPreference = 'Stop'

$PROJECT  = 'celltech-internal-tools'
$LOCATION = 'us-central1'
$TRIGGER  = 'scheduler-sunset-trigger'
$HOUR     = 12                      # noon
$TZ_ID    = 'Pacific Standard Time' # Windows name; handles PDT/PST automatically
$TZ_GCP   = 'America/Los_Angeles'

function Write-Step($msg) { Write-Host "`n$msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "  OK  $msg" -ForegroundColor Green }
function Write-Bad($msg)  { Write-Host "  !!  $msg" -ForegroundColor Red }

Write-Host "=======================================================" -ForegroundColor White
Write-Host " Reschedule schedule-teardown  ($TRIGGER)" -ForegroundColor White
Write-Host " Sets the date that ALL Cloud Scheduler jobs are" -ForegroundColor White
Write-Host " snapshotted, paused and deleted. Always noon Pacific." -ForegroundColor White
Write-Host "=======================================================" -ForegroundColor White

# ── gcloud present? ─────────────────────────────────────────────────────────
if (-not (Get-Command gcloud -ErrorAction SilentlyContinue)) {
    $fallback = 'C:\Program Files (x86)\Google\Cloud SDK\google-cloud-sdk\bin'
    if (Test-Path (Join-Path $fallback 'gcloud.cmd')) {
        $env:Path = "$env:Path;$fallback"
    } else {
        Write-Bad 'gcloud is not on PATH. Open the Google Cloud SDK Shell and run this from there.'
        exit 1
    }
}

# ── 1. Show the current setting ─────────────────────────────────────────────
Write-Step 'Current trigger:'
$current = gcloud scheduler jobs describe $TRIGGER --location=$LOCATION --project=$PROJECT --format='value(state,schedule,scheduleTime)'
if ($LASTEXITCODE -ne 0) {
    Write-Bad "Could not read $TRIGGER. Are you logged in? Try: gcloud auth login"
    exit 1
}
$cur = $current -split "`t"
Write-Host "  State:    $($cur[0])"
Write-Host "  Cron:     $($cur[1])"
if ($cur[2]) {
    $curLocal = [System.TimeZoneInfo]::ConvertTimeFromUtc(
        [datetime]::Parse($cur[2], $null, 'AdjustToUniversal'),
        [System.TimeZoneInfo]::FindSystemTimeZoneById($TZ_ID))
    Write-Host "  Next run: $($curLocal.ToString('dddd, MMMM d yyyy, h:mm tt')) Pacific"
}

# ── 2. Ask for the new date, until it's valid ───────────────────────────────
$target = $null
while (-not $target) {
    Write-Host ''
    $answer = Read-Host 'New removal date (YYYY-MM-DD, or Q to quit)'
    if ($answer -match '^\s*[Qq]\s*$' -or $answer -eq '') {
        Write-Host 'Cancelled. Nothing changed.' -ForegroundColor Yellow
        exit 0
    }
    $parsed = [datetime]::MinValue
    $ok = [datetime]::TryParseExact($answer.Trim(), 'yyyy-MM-dd',
        [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$parsed)
    if (-not $ok) {
        Write-Bad "Not a valid date. Use YYYY-MM-DD, for example 2026-10-09."
        continue
    }
    $when = $parsed.Date.AddHours($HOUR)
    $nowPacific = [System.TimeZoneInfo]::ConvertTimeFromUtc(
        [datetime]::UtcNow, [System.TimeZoneInfo]::FindSystemTimeZoneById($TZ_ID))
    if ($when -le $nowPacific) {
        Write-Bad "$($when.ToString('yyyy-MM-dd')) noon Pacific is in the past. Pick a later date."
        continue
    }
    if ($when -gt $nowPacific.AddYears(1)) {
        Write-Bad 'More than a year out. The cron repeats yearly, so pick a date within 12 months.'
        continue
    }
    $target = $when
}

$schedule = "0 $HOUR $($target.Day) $($target.Month) *"

Write-Host ''
Write-Host "  Will delete every schedule on: " -NoNewline
Write-Host $target.ToString('dddd, MMMM d yyyy, h:mm tt') -ForegroundColor Yellow -NoNewline
Write-Host ' Pacific'
Write-Host "  Cron: $schedule ($TZ_GCP)"
$confirm = Read-Host 'Apply this? (y/n)'
if ($confirm -notmatch '^\s*[Yy]') {
    Write-Host 'Cancelled. Nothing changed.' -ForegroundColor Yellow
    exit 0
}

# ── 3. Apply ────────────────────────────────────────────────────────────────
Write-Step 'Updating trigger...'
gcloud scheduler jobs update http $TRIGGER --location=$LOCATION --project=$PROJECT --schedule="$schedule" --time-zone="$TZ_GCP" --quiet --format='none'
if ($LASTEXITCODE -ne 0) { Write-Bad 'Update failed. Nothing was changed.'; exit 1 }
Write-Ok 'Schedule updated.'

$state = gcloud scheduler jobs describe $TRIGGER --location=$LOCATION --project=$PROJECT --format='value(state)'
if ($state -eq 'PAUSED') {
    Write-Step 'Trigger was paused (a teardown already ran). Resuming...'
    gcloud scheduler jobs resume $TRIGGER --location=$LOCATION --project=$PROJECT --quiet --format='none'
    if ($LASTEXITCODE -ne 0) { Write-Bad 'Resume failed — the trigger is still PAUSED and will NOT fire.'; exit 1 }
    Write-Ok 'Resumed.'
}

# ── 4. Verify by reading it back ────────────────────────────────────────────
Write-Step 'Verifying...'
Start-Sleep -Seconds 2
$after = (gcloud scheduler jobs describe $TRIGGER --location=$LOCATION --project=$PROJECT --format='value(state,schedule,timeZone,scheduleTime)') -split "`t"
if ($LASTEXITCODE -ne 0) { Write-Bad 'Could not read the trigger back. Check the console.'; exit 1 }

$problems = @()
if ($after[1] -ne $schedule)  { $problems += "cron is '$($after[1])', expected '$schedule'" }
if ($after[2] -ne $TZ_GCP)    { $problems += "time zone is '$($after[2])', expected '$TZ_GCP'" }
if ($after[0] -ne 'ENABLED')  { $problems += "state is '$($after[0])', so it will NOT fire" }

$nextLocal = $null
if ($after[3]) {
    $nextLocal = [System.TimeZoneInfo]::ConvertTimeFromUtc(
        [datetime]::Parse($after[3], $null, 'AdjustToUniversal'),
        [System.TimeZoneInfo]::FindSystemTimeZoneById($TZ_ID))
    if ($nextLocal.Date -ne $target.Date) {
        $problems += "next run is $($nextLocal.ToString('yyyy-MM-dd HH:mm')) Pacific, expected $($target.ToString('yyyy-MM-dd HH:mm'))"
    }
}

Write-Host ''
if ($problems.Count -eq 0) {
    Write-Host '  VERIFIED' -ForegroundColor Green
    Write-Ok "State:    $($after[0])"
    Write-Ok "Cron:     $($after[1])  ($($after[2]))"
    Write-Ok "Next run: $($nextLocal.ToString('dddd, MMMM d yyyy, h:mm tt')) Pacific"
    Write-Host ''
    Write-Host '  Every Cloud Scheduler job in the project will be snapshotted to' -ForegroundColor White
    Write-Host '  gs://celltech-internal-tools-scheduler-snapshots and then deleted.' -ForegroundColor White
    Write-Host '  Bring them all back with:  restore-schedules.bat' -ForegroundColor White
} else {
    Write-Host '  VERIFY FAILED' -ForegroundColor Red
    $problems | ForEach-Object { Write-Bad $_ }
    Write-Host '  Fix this before walking away.' -ForegroundColor Red
    exit 1
}
