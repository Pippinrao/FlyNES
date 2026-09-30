[CmdletBinding()]
param(
    [string]$AndroidSerial = 'emulator-5582',
    [string]$HarmonyTarget = '127.0.0.1:5557',
    [Parameter(Mandatory)][string]$HarmonyAppPath,
    [Parameter(Mandatory)][string]$HarmonyTestPath,
    [string]$ZlibRoot = 'E:/workspace/codes/games/FlyNES/.artifacts/host-deps/zlib-1.3.1-install',
    [ValidateSet('Both', 'Android', 'Harmony')][string]$HostDirection = 'Both'
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
Set-Location $repo
$adb = Join-Path $env:LOCALAPPDATA 'Android/Sdk/platform-tools/adb.exe'
$hdc = 'D:/soft/DevEco Studio/sdk/default/openharmony/toolchains/hdc.exe'
if ($AndroidSerial -notlike 'emulator-*' -or $HarmonyTarget -notmatch '^127\.0\.0\.1:\d+$') {
    throw 'This runner certifies simulator NAT only'
}
if ((& $adb -s $AndroidSerial shell getprop ro.kernel.qemu).Trim() -ne '1') { throw 'Android emulator required' }
if ((& $hdc list targets) -notcontains $HarmonyTarget) { throw 'Harmony target unavailable' }
$evidence = Join-Path $repo ('.artifacts/flutter-g2/nearby/' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $evidence -Force | Out-Null
@("git=$(git rev-parse HEAD)", "direction=$HostDirection", 'transport=task-owned-simulator-NAT; opticalQr=false; physicalLAN=false',
    "appApk=$((Get-FileHash app/build/outputs/apk/debug/app-debug.apk).Hash)",
    "testApk=$((Get-FileHash app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk).Hash)",
    "appHap=$((Get-FileHash $HarmonyAppPath).Hash)", "testHap=$((Get-FileHash $HarmonyTestPath).Hash)") |
    Set-Content (Join-Path $evidence 'run.txt')

# Packages must already be installed with replacement install; this runner never
# installs, uninstalls, resets preferences or alters a global network/firewall.
if ($HostDirection -in @('Both', 'Android')) {
    & pwsh -NoProfile -File tools/quality/run_nearby_mvp.ps1 -AndroidSerial $AndroidSerial -HarmonyTarget $HarmonyTarget `
        -HarmonyAppPath $HarmonyAppPath -HarmonyTestPath $HarmonyTestPath -ZlibRoot $ZlibRoot `
        -CrossOnly -ProductPlay -CrossRounds 1 -CrossDurationMinutes 0 -PlayHoldSeconds 10 *> (Join-Path $evidence 'android-host.log')
    if ($LASTEXITCODE -ne 0) { throw "Android host failed: $evidence" }
}
if ($HostDirection -in @('Both', 'Harmony')) {
    $relay = $null; $hostTest = $null; $guestTest = $null
    $passed = $false
    try {
        & $adb -s $AndroidSerial shell am force-stop com.flynes.emu | Out-Null
        & $hdc -t $HarmonyTarget shell aa force-stop com.flynes.emu | Out-Null
        & $hdc -t $HarmonyTarget shell rm -f /data/app/el2/100/base/com.flynes.emu/haps/entry/files/nearby-cross-host-invite.txt | Out-Null
        $port = Get-Random -Minimum 44000 -Maximum 49000
        $token = [Guid]::NewGuid().ToString('N')
        $relay = Start-Process -FilePath (Get-Command python).Source -WindowStyle Hidden -PassThru `
            -ArgumentList @('tools/quality/nearby_g2_relay.py', '--port', $port, '--token', $token, '--seconds', 180) `
            -RedirectStandardOutput (Join-Path $evidence 'relay.log') -RedirectStandardError (Join-Path $evidence 'relay-error.log')
        Start-Sleep -Milliseconds 500
        if ($relay.HasExited) { throw 'Relay could not bind task port' }
        $hostArgs = @('-t', $HarmonyTarget, 'shell', 'aa', 'test', '-b', 'com.flynes.emu', '-m', 'entry_test',
            '-s', 'unittest', 'OpenHarmonyTestRunner', '-s', 'timeout', '160000', '-s', 'nearbyExternalHostOnly', 'true',
            '-s', 'simulatorRelayPort', $port, '-s', 'simulatorRelayToken', $token)
        $hostTest = Start-Process -FilePath $hdc -WindowStyle Hidden -PassThru -ArgumentList $hostArgs `
            -RedirectStandardOutput (Join-Path $evidence 'harmony-host.log') -RedirectStandardError (Join-Path $evidence 'harmony-host-error.log')
        $invite = ''; $deadline = [DateTime]::UtcNow.AddSeconds(40)
        while ([DateTime]::UtcNow -lt $deadline -and $invite -notmatch '^flynes-lan-v1:') {
            Start-Sleep -Milliseconds 100
            $invite = ((& $hdc -t $HarmonyTarget shell cat /data/app/el2/100/base/com.flynes.emu/haps/entry/files/nearby-cross-host-invite.txt 2>$null) -join '').Trim()
        }
        if ($invite -notmatch '^flynes-lan-v1:[^:]+:\d+:[a-fA-F0-9]+:[a-fA-F0-9]+$') { throw 'Harmony did not publish valid native invitation' }
        $guestArgs = @('-s', $AndroidSerial, 'shell', 'am', 'instrument', '-w', '-r', '-e', 'class',
            'com.flynes.emu.NearbyMvpExternalGuestTest', '-e', 'crossAppInvite', $invite,
            '-e', 'simulatorRelayPort', $port, '-e', 'simulatorRelayToken', $token, '-e', 'playHoldMs', '100000',
            'com.flynes.emu.test/com.flynes.emu.test.SingleDeviceCertificationRunner')
        $guestTest = Start-Process -FilePath $adb -WindowStyle Hidden -PassThru -ArgumentList $guestArgs `
            -RedirectStandardOutput (Join-Path $evidence 'android-guest.log') -RedirectStandardError (Join-Path $evidence 'android-guest-error.log')
        $deadline = [DateTime]::UtcNow.AddSeconds(170)
        while ((!$hostTest.HasExited -or !$guestTest.HasExited) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Seconds 1 }
        if (!$hostTest.HasExited -or !$guestTest.HasExited) { throw 'Reverse product play timed out' }
        $hostOutput = Get-Content (Join-Path $evidence 'harmony-host.log') -Raw
        $guestOutput = Get-Content (Join-Path $evidence 'android-guest.log') -Raw
        if ($hostOutput -notmatch 'Tests run: 1, Failure: 0, Error: 0, Pass: 1, Ignore: 0') { throw 'Harmony host did not pass exactly one real product test' }
        if ($guestOutput -notmatch 'OK \(1 test\)' -or $guestOutput -match 'FAILURES!!!|Process crashed|INSTRUMENTATION_FAILED') { throw 'Android guest did not pass exactly one real product test' }
        $passed = $true
    } finally {
        foreach ($process in @($hostTest, $guestTest, $relay)) { if ($process -and !$process.HasExited) { $process.Kill(); $process.WaitForExit() } }
        & $adb -s $AndroidSerial logcat -d -s FlyNesNearby | Set-Content (Join-Path $evidence 'android-nearby.log')
        & $hdc -t $HarmonyTarget shell hilog -x -T FlyNesNearby | Set-Content (Join-Path $evidence 'harmony-nearby.log')
        if (!$passed) {
            Add-Content (Join-Path $evidence 'run.txt') 'result=FAIL'
            & $adb -s $AndroidSerial shell am force-stop com.flynes.emu | Out-Null
            & $hdc -t $HarmonyTarget shell aa force-stop com.flynes.emu | Out-Null
        }
    }
}
Add-Content (Join-Path $evidence 'run.txt') 'result=PASS'
Write-Host "PASS G2 nearby $HostDirection host: $evidence"
