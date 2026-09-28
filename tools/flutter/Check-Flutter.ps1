param([string]$FlutterCommand = 'flutter')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$moduleRoot = Join-Path $repoRoot 'ui/flutter'
$flutterPath = (Get-Command $FlutterCommand -ErrorAction Stop).Source
$dartName = if ($IsWindows) { 'dart.bat' } else { 'dart' }
$dartPath = Join-Path (Split-Path $flutterPath) $dartName
if (-not (Test-Path -LiteralPath $dartPath)) {
    throw 'Use the Flutter SDK bin executable so the matching Dart SDK can be located.'
}

Push-Location $moduleRoot
try {
    & $flutterPath --suppress-analytics pub get
    if ($LASTEXITCODE -ne 0) { throw 'Flutter dependency resolution failed.' }
    & $dartPath format --output=none --set-exit-if-changed lib test
    if ($LASTEXITCODE -ne 0) { throw 'Dart formatting check failed.' }
    & $flutterPath --suppress-analytics analyze --no-pub
    if ($LASTEXITCODE -ne 0) { throw 'Flutter analysis failed.' }
    & $flutterPath --suppress-analytics test --no-pub --reporter expanded
    if ($LASTEXITCODE -ne 0) { throw 'Flutter widget tests failed.' }
} finally {
    Pop-Location
}
