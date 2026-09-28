param(
    [string]$FlutterCommand = 'flutter',
    [ValidateSet('Debug', 'Release')][string]$Configuration = 'Debug',
    [switch]$IncludeTests
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$flutterPath = (Get-Command $FlutterCommand -ErrorAction Stop).Source
$sdk = (& $flutterPath --version --machine | Out-String | ConvertFrom-Json)
if ($LASTEXITCODE -ne 0) { throw 'Unable to read Flutter SDK identity.' }
if ($sdk.frameworkVersion -ne '3.41.7' -or
    $sdk.frameworkRevision -ne 'cc0734ac716fbb8b90f3f9db8020958b1553afa7' -or
    $sdk.engineRevision -ne '59aa584fdf100e6c78c785d8a5b565d1de4b48ab' -or
    $sdk.dartSdkVersion -ne '3.11.5') {
    throw 'Android G1 requires the pinned Flutter 3.41.7 framework/engine and Dart 3.11.5. Update the reviewed toolchain pin before using another SDK.'
}
Push-Location (Join-Path $repoRoot 'ui/flutter')
try {
    & $flutterPath --suppress-analytics pub get
    if ($LASTEXITCODE -ne 0) { throw 'Flutter module generation failed.' }
} finally { Pop-Location }
Push-Location $repoRoot
try {
    $gradleTasks = @(':app:assemble' + $Configuration)
    if ($IncludeTests) {
        if ($Configuration -ne 'Debug') { throw 'Instrumentation uses the debug test package.' }
        $gradleTasks += ':app:testDebugUnitTest', ':app:assembleDebugAndroidTest'
    }
    & ./gradlew.bat @gradleTasks
    if ($LASTEXITCODE -ne 0) { throw 'Android production-host build failed.' }
} finally { Pop-Location }
