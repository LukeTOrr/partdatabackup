# Reschedule the one-shot trigger that tears down every Cloud Scheduler job.
# Driven by set-removal-date.bat — double-click that, don't run this directly.
# Time is always 12:00 PM Pacific; only the date changes.
#
# Nothing here exits on a recoverable problem: auth trouble offers a login and
# retries, any other gcloud failure offers a retry. You always get a clear ending.

$ErrorActionPreference = 'Continue'   # gcloud writes to stderr; don't let that throw

$PROJECT  = 'celltech-internal-tools'
$LOCATION = 'us-central1'
$TRIGGER  = 'scheduler-sunset-trigger'
$HOUR     = 12                        # noon
$TZ_ID    = 'Pacific Standard Time'   # Windows name; handles PDT/PST automatically
$TZ_GCP   = 'America/Los_Angeles'

function Write-Step($msg) { Write-Host "`n$msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "  OK  $msg" -ForegroundColor Green }
function Write-Bad($msg)  { Write-Host "  !!  $msg" -ForegroundColor Red }

function Get-Pacific([datetime]$utc) {
    [System.TimeZoneInfo]::ConvertTimeFromUtc($utc, [System.TimeZoneInfo]::FindSystemTimeZoneById($TZ_ID))
}

# ── Make sure gcloud is callable; wait for the user instead of giving up ────
function Wait-ForGcloud {
    while (-not (Get-Command gcloud -ErrorAction SilentlyContinue)) {
        $sdk = 'C:\Program Files (x86)\Google\Cloud SDK\google-cloud-sdk\bin'
        if (Test-Path (Join-Path $sdk 'gcloud.cmd')) { $env:Path = "$env:Path;$sdk"; break }
        Write-Bad 'gcloud is not on PATH.'
        Write-Host '  Install/open the Google Cloud SDK, then press Enter to look again (or type Q to quit).'
        if ((Read-Host '  Enter to retry') -match '^\s*[Qq]') { return $false }
    }
    return $true
}

# ── One place where every gcloud call happens ───────────────────────────────
# Returns the trimmed stdout on success, or $null if the user chose to quit.
function Invoke-Gcloud {
    param([string[]]$GcloudArgs, [string]$What)
    while ($true) {
        $raw  = & gcloud @GcloudArgs 2>&1 | Out-String
        $code = $LASTEXITCODE
        if ($code -eq 0) { return $raw.Trim() }

        Write-Bad "$What failed."
        $msg = $raw.Trim()
        if ($msg) { Write-Host ($msg -split "`n" | Select-Object -First 6 | ForEach-Object { "     $_" }) -ForegroundColor DarkGray }

        $looksLikeAuth = $msg -match 'Reauthentication|auth login|do not currently have an active account|credentials|invalid_grant|Your current credentials'
        if ($looksLikeAuth) {
            Write-Host ''
            Write-Host '  This looks like a login problem.' -ForegroundColor Yellow
            $ans = Read-Host '  [L] log in now   [R] retry   [Q] quit'
            if ($ans -match '^\s*[Qq]') { return $null }
            if ($ans -match '^\s*[Ll]' -or $ans -eq '') {
                Write-Step 'Opening the Google login. Finish it in your browser, then come back here...'
                & gcloud auth login
                if ($LASTEXITCODE -ne 0) { Write-Bad 'Login did not complete. You can try again.' }
                else { Write-Ok 'Logged in. Retrying...' }
            }
        } else {
            Write-Host ''
            $ans = Read-Host '  [R] retry   [Q] quit'
            if ($ans -match '^\s*[Qq]') { return $null }
        }
    }
}

function Show-Trigger($label) {
    $out = Invoke-Gcloud @('scheduler','jobs','describe',$TRIGGER,"--location=$LOCATION","--project=$PROJECT",
                           '--format=value(state,schedule,timeZone,scheduleTime)') "Reading $TRIGGER"
    if ($null -eq $out) { return $null }
    $f = $out -split "`t"
    $next = if ($f.Count -ge 4 -and $f[3]) { Get-Pacific ([datetime]::Parse($f[3], $null, 'AdjustToUniversal')) } else { $null }
    if ($label) {
        Write-Host "  State:    $($f[0])"
        Write-Host "  Cron:     $($f[1])   ($($f[2]))"
        if ($next) { Write-Host "  Next run: $($next.ToString('dddd, MMMM d yyyy, h:mm tt')) Pacific" }
        else       { Write-Host "  Next run: (none - trigger is $($f[0]))" }
    }
    return [pscustomobject]@{ State = $f[0]; Schedule = $f[1]; TimeZone = $f[2]; Next = $next }
}

# ═══════════════════════════════════════════════════════════════════════════
Write-Host "=======================================================" -ForegroundColor White
Write-Host " Reschedule schedule-teardown  ($TRIGGER)" -ForegroundColor White
Write-Host " Sets the date that ALL Cloud Scheduler jobs are" -ForegroundColor White
Write-Host " snapshotted, paused and deleted. Always noon Pacific." -ForegroundColor White
Write-Host "=======================================================" -ForegroundColor White

if (-not (Wait-ForGcloud)) { Write-Host 'Quit. Nothing changed.' -ForegroundColor Yellow; exit 1 }

Write-Step 'Current trigger:'
$before = Show-Trigger $true
if ($null -eq $before) { Write-Host "`nQuit. Nothing changed." -ForegroundColor Yellow; exit 1 }

# ── Ask for the new date, until it's valid ──────────────────────────────────
$target = $null
while (-not $target) {
    Write-Host ''
    $answer = Read-Host 'New removal date (YYYY-MM-DD, or Q to quit)'
    if ($null -eq $answer -or $answer.Trim() -eq '' -or $answer -match '^\s*[Qq]\s*$') {
        Write-Host 'Cancelled. Nothing changed.' -ForegroundColor Yellow; exit 0
    }
    $parsed = [datetime]::MinValue
    $ok = [datetime]::TryParseExact($answer.Trim(), 'yyyy-MM-dd',
        [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$parsed)
    if (-not $ok) { Write-Bad 'Not a valid date. Use YYYY-MM-DD, for example 2026-10-09.'; continue }

    $when = $parsed.Date.AddHours($HOUR)
    $nowPacific = Get-Pacific ([datetime]::UtcNow)
    if ($when -le $nowPacific) {
        Write-Bad "$($when.ToString('yyyy-MM-dd')) noon Pacific has already passed. Pick a later date."; continue
    }
    if ($when -gt $nowPacific.AddYears(1)) {
        Write-Bad 'More than a year out. The cron repeats yearly, so pick a date within 12 months.'; continue
    }
    $target = $when
}

$schedule = "0 $HOUR $($target.Day) $($target.Month) *"
$daysAway = [math]::Round(($target - (Get-Pacific ([datetime]::UtcNow))).TotalDays, 1)

Write-Host ''
Write-Host '  Will delete every schedule on: ' -NoNewline
Write-Host $target.ToString('dddd, MMMM d yyyy, h:mm tt') -ForegroundColor Yellow -NoNewline
Write-Host " Pacific  ($daysAway days away)"
Write-Host "  Cron: $schedule ($TZ_GCP)"
$confirm = Read-Host 'Apply this? (y/n)'
if ($confirm -notmatch '^\s*[Yy]') { Write-Host 'Cancelled. Nothing changed.' -ForegroundColor Yellow; exit 0 }

# ── Apply ───────────────────────────────────────────────────────────────────
Write-Step 'Updating trigger...'
$upd = Invoke-Gcloud @('scheduler','jobs','update','http',$TRIGGER,"--location=$LOCATION","--project=$PROJECT",
                       "--schedule=$schedule","--time-zone=$TZ_GCP",'--quiet','--format=none') 'Updating the schedule'
if ($null -eq $upd) { Write-Host "`nQuit before the update went through. Nothing changed." -ForegroundColor Yellow; exit 1 }
Write-Ok 'Schedule updated.'

$state = Invoke-Gcloud @('scheduler','jobs','describe',$TRIGGER,"--location=$LOCATION","--project=$PROJECT",
                         '--format=value(state)') 'Checking the trigger state'
if ($state -eq 'PAUSED') {
    Write-Step 'Trigger was paused (a teardown already ran). Resuming...'
    $res = Invoke-Gcloud @('scheduler','jobs','resume',$TRIGGER,"--location=$LOCATION","--project=$PROJECT",
                           '--quiet','--format=none') 'Resuming the trigger'
    if ($null -eq $res) { Write-Bad 'Still PAUSED - the date is set but it will NOT fire. Re-run this and choose Resume.'; exit 1 }
    Write-Ok 'Resumed.'
}

# ── Verify by reading it back ───────────────────────────────────────────────
Write-Step 'Verifying...'
Start-Sleep -Seconds 2
$after = Show-Trigger $false
if ($null -eq $after) { Write-Bad 'Could not read the trigger back. Check the Cloud Scheduler console.'; exit 1 }

$problems = @()
if ($after.Schedule -ne $schedule) { $problems += "cron is '$($after.Schedule)', expected '$schedule'" }
if ($after.TimeZone -ne $TZ_GCP)   { $problems += "time zone is '$($after.TimeZone)', expected '$TZ_GCP'" }
if ($after.State -ne 'ENABLED')    { $problems += "state is '$($after.State)', so it will NOT fire" }
if ($after.Next -and $after.Next.Date -ne $target.Date) {
    $problems += "next run is $($after.Next.ToString('yyyy-MM-dd HH:mm')) Pacific, expected $($target.ToString('yyyy-MM-dd HH:mm'))"
}
if (-not $after.Next) { $problems += 'no next run time reported' }

Write-Host ''
if ($problems.Count -eq 0) {
    Write-Host '  VERIFIED' -ForegroundColor Green
    Write-Ok "State:    $($after.State)"
    Write-Ok "Cron:     $($after.Schedule)   ($($after.TimeZone))"
    Write-Ok "Next run: $($after.Next.ToString('dddd, MMMM d yyyy, h:mm tt')) Pacific"
    Write-Host ''
    Write-Host '  On that date every Cloud Scheduler job in the project is snapshotted to' -ForegroundColor White
    Write-Host '  gs://celltech-internal-tools-scheduler-snapshots and then deleted.' -ForegroundColor White
    Write-Host '  Bring them all back any time with:  restore-schedules.bat' -ForegroundColor White
    exit 0
} else {
    Write-Host '  VERIFY FAILED' -ForegroundColor Red
    $problems | ForEach-Object { Write-Bad $_ }
    Write-Host '  Fix this before walking away.' -ForegroundColor Red
    exit 1
}
