[CmdletBinding()]
param(
  [string]$Serial = '127.0.0.1:5557',
  [ValidateSet('native', 'flutter')][string]$Route = 'native',
  [switch]$CandidateApproved,
  [ValidateRange(0, 10)][int]$Warmups = 2,
  [ValidateRange(1, 50)][int]$Samples = 12,
  [Parameter(Mandatory)][string]$OutputDirectory,
  [string]$Hdc = 'D:/soft/DevEco Studio/sdk/default/openharmony/toolchains/hdc.exe'
)
$ErrorActionPreference = 'Stop'
if ($Serial -eq '127.0.0.1:5555') { throw 'The user HVD 5555 is not a performance target.' }
if ($Route -eq 'flutter' -and -not $CandidateApproved) {
  throw 'Flutter startup requires explicit confirmed numerical budget approval.'
}
if (Test-Path -LiteralPath $OutputDirectory) { throw 'Evidence directory already exists; choose a new path.' }
$output = New-Item -ItemType Directory -Path $OutputDirectory
$rows = [System.Collections.Generic.List[object]]::new()
$pids = [System.Collections.Generic.HashSet[int]]::new()
$lastCode = 0
try {
  & $Hdc -t $Serial shell bm dump -n com.flynes.emu > (Join-Path $output.FullName 'bundle-before.json')
  if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect installed bundle.' }
  for ($index = 0; $index -lt ($Warmups + $Samples); $index++) {
    $phase = if ($index -lt $Warmups) { 'warmup' } else { 'measured' }
    $sample = '{0}-{1:d2}' -f $phase, $index
    & $Hdc -t $Serial shell aa force-stop com.flynes.emu > (Join-Path $output.FullName "$sample-stop.log")
    if ($LASTEXITCODE -ne 0) { throw 'force-stop failed; fresh process cannot be claimed.' }
    $remaining = (& $Hdc -t $Serial shell pidof com.flynes.emu | Out-String).Trim()
    if ($remaining -match '^\d') { throw "Application process survived force-stop: $remaining" }
    $log = Join-Path $output.FullName "$sample-hypium.log"
    $testArgs = @('-t', $Serial, 'shell', 'aa', 'test', '-b', 'com.flynes.emu', '-m', 'entry_test',
      '-s', 'unittest', 'OpenHarmonyTestRunner', '-s', 'g1StartupObservation', 'true',
      '-s', 'g1Entry', $Route, '-s', 'g1BuildMode', 'debug', '-s', 'g1Sample', $sample,
      '-s', 'timeout', '60000')
    if ($CandidateApproved) { $testArgs += @('-s', 'g1CandidateApproved', 'true') }
    & $Hdc @testArgs *> $log
    $testExit = $LASTEXITCODE
    $locations = (& $Hdc -t $Serial shell find /data/app/el2/100/base/com.flynes.emu -name "g1-startup-$Route.json" 2>&1 |
      Where-Object { "$_" -match '^/data/.*/g1-startup-' })
    $received = $false
    $locationIndex = 0
    foreach ($location in $locations) {
      $candidate = Join-Path $output.FullName "$sample-$locationIndex.json"
      $locationIndex++
      & $Hdc -t $Serial file recv "$location" $candidate > (Join-Path $output.FullName "$sample-recv.log")
      if ($LASTEXITCODE -ne 0) { continue }
      $report = Get-Content -LiteralPath $candidate -Raw | ConvertFrom-Json
      if ($report.sample -ne $sample) { continue }
      $received = $true
      if (-not $report.complete -or $report.failure -or $report.route -ne $Route) {
        throw "Incomplete/failed startup report: $candidate"
      }
      if (-not $pids.Add([int]$report.pid)) { throw 'Repeated PID; investigate fresh-process isolation.' }
      $rows.Add([pscustomobject]@{ phase=$phase; sample=$sample; pid=$report.pid;
        primaryInteractiveMs=$report.primaryInteractiveMs; firstVisibleCardMs=$report.firstVisibleCardMs;
        nativeSnapshotCount=$report.nativeSnapshotCount; projectedDirectoryCount=$report.projectedDirectoryCount;
        pssKb=$report.pssKb; debug=$report.debug; buildMode=$report.buildMode;
        json=(Split-Path -Leaf $candidate); sha256=(Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash })
      break
    }
    if (-not $received) { throw "No current JSON for $sample; inspect retained Hypium log." }
    $result = Get-Content -LiteralPath $log -Raw
    if ($testExit -ne 0 -or $result -notmatch 'Tests run: 1, Failure: 0, Error: 0, Pass: 1') {
      throw "Hypium did not pass for $sample (exit $testExit)."
    }
    Write-Host "$sample PASS pid=$($report.pid) primary=$($report.primaryInteractiveMs)ms card=$($report.firstVisibleCardMs)ms"
  }
} catch {
  $_ | Out-String | Set-Content -LiteralPath (Join-Path $output.FullName 'failure.txt')
  $lastCode = 1
} finally {
  $rows.ToArray() | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $output.FullName 'samples.json')
}
if ($lastCode -ne 0) { throw "Startup collection failed; evidence preserved in $($output.FullName)" }
if (($rows | Where-Object phase -eq 'measured').Count -ne $Samples) { throw 'Measured sample count mismatch.' }
Write-Host "Recorded $Warmups warmups and $Samples $Route observations in $($output.FullName)"
