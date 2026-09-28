[CmdletBinding()]
param(
  [string] $FlutterSdk = 'E:/workspace/lib/flutter/flutter-ohos-3.41.10-1.0.0',
  [string] $DevEco = 'D:/soft/DevEco Studio',
  [string] $PubCache = 'E:/workspace/lib/flutter/oh-pub',
  [switch] $BuildTests
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$revision = (& git -C $FlutterSdk rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $revision -ne '244a0e8abb3085e8675589b13e219af8c41cb7aa') {
  throw 'REQ-004 probe requires the pinned Flutter-OH 3.41.10-ohos-1.0.0 commit.'
}
$run = Join-Path $repo ('.artifacts/oh/' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
$module = Join-Path $run 'module'
$bin = Join-Path $run 'bin'
$node = Join-Path $DevEco 'tools/node/node.exe'
$ohpmCli = Join-Path $DevEco 'tools/ohpm/bin/pm-cli.js'
$hvigor = Join-Path $DevEco 'tools/hvigor/bin/hvigorw.js'
$flutter = Join-Path $FlutterSdk 'bin/flutter.bat'
foreach ($file in @($node, $ohpmCli, $hvigor, $flutter)) {
  if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Missing tool: $file" }
}
New-Item -ItemType Directory -Path $module, $bin | Out-Null
Copy-Item -LiteralPath (Join-Path $repo 'ui/flutter/lib'), (Join-Path $repo 'ui/flutter/test') -Destination $module -Recurse
foreach ($name in @('pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml', '.metadata')) {
  Copy-Item -LiteralPath (Join-Path $repo "ui/flutter/$name") -Destination $module
}
$ohpmShim = Join-Path $bin 'ohpm.bat'
@('@echo off', ('"' + $node + '" "' + $ohpmCli + '" %*'), 'exit /b %errorlevel%') |
  Set-Content -LiteralPath $ohpmShim -Encoding ascii
$envNames = @('DEVECO_SDK_HOME', 'PUB_CACHE', 'PUB_HOSTED_URL', 'FLUTTER_STORAGE_BASE_URL', 'FLUTTER_GIT_URL', 'PATH')
$savedEnvironment = @{}
foreach ($name in $envNames) { $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
function Invoke-Recorded([string] $Name, [string] $Executable, [string[]] $Arguments) {
  & $Executable @Arguments *> (Join-Path $run "$Name.log")
  $commandExit = $LASTEXITCODE
  "exitCode=$commandExit" | Set-Content (Join-Path $run "$Name.exit.txt")
  if ($commandExit -ne 0) { throw "$Name failed (exit $commandExit). See $run/$Name.log" }
}
try {
  $env:DEVECO_SDK_HOME = Join-Path $DevEco 'sdk'
  $env:PUB_CACHE = $PubCache
  $env:PUB_HOSTED_URL = 'https://pub.flutter-io.cn'
  $env:FLUTTER_STORAGE_BASE_URL = 'https://storage.flutter-io.cn'
  $env:FLUTTER_GIT_URL = 'https://gitcode.com/CPF-Flutter/flutter_flutter.git'
  $env:PATH = "$bin;$(Join-Path $FlutterSdk 'bin');$(Join-Path $DevEco 'tools/node');$(Join-Path $DevEco 'tools/hvigor/bin');" + $env:PATH
  Push-Location $module
  try {
    Invoke-Recorded 'version' $flutter @('--version', '--machine')
    Invoke-Recorded 'pub-get' $flutter @('pub', 'get')
    $config = Join-Path $module '.ohos/hvigorconfig.ts'
    $shimForTs = $ohpmShim.Replace('\', '/')
    $configText = Get-Content -LiteralPath $config -Raw
    $configText.Replace('injectNativeModules(__dirname', "process.env.ohpmBin = '$shimForTs';`ninjectNativeModules(__dirname") |
      Set-Content -LiteralPath $config
    # The generated module inherits the production host's supported OS floor.
    # The pinned 1.0.0 embedding itself declares API12; do not raise the app floor
    # merely because Flutter's new-project template defaults to API18.
    $hostProfile = Get-Content (Join-Path $repo 'harmony/build-profile.json5') -Raw
    $hostMinimum = [regex]::Match($hostProfile, '"compatibleSdkVersion"\s*:\s*"([^"]+)"').Groups[1].Value
    if (-not $hostMinimum) { throw 'Production host minimum SDK was not found.' }
    $moduleProfile = Join-Path $module '.ohos/build-profile.json5'
    $profileText = Get-Content -LiteralPath $moduleProfile -Raw
    [regex]::Replace($profileText, '"compatibleSdkVersion"\s*:\s*"[^"]+"', ('"compatibleSdkVersion": "' + $hostMinimum + '"')) |
      Set-Content -LiteralPath $moduleProfile
    Invoke-Recorded 'har-debug' $flutter @('build', 'har', '--debug', '--target-platform', 'ohos-arm64,ohos-x64', '--no-pub')
  } finally { Pop-Location }
  $harDestination = Join-Path $repo 'harmony/.artifacts/flutter-har'
  New-Item -ItemType Directory -Path $harDestination -Force | Out-Null
  Copy-Item -Path (Join-Path $module 'build/ohos/har/debug/*.har') -Destination $harDestination -Force
  Get-ChildItem -LiteralPath $harDestination -Filter '*.har' | Get-FileHash -Algorithm SHA256 |
    Select-Object Path,Hash | ConvertTo-Json | Set-Content (Join-Path $run 'har-hashes.json')
  & (Join-Path $repo 'tools/content/sync-builtin-content.ps1') -Root $repo
  if ($LASTEXITCODE -ne 0) { throw 'Content staging failed.' }
  Push-Location (Join-Path $repo 'harmony')
  try {
    Invoke-Recorded 'ohpm-install' $node @($ohpmCli, 'install', '--all')
    Invoke-Recorded 'hap-debug' $node @($hvigor, '--mode', 'module', '-p', 'product=default', '-p', 'buildMode=debug', 'assembleHap', '--no-daemon')
    if ($BuildTests) {
      Invoke-Recorded 'hap-tests' $node @($hvigor, '--mode', 'module', '-p', 'product=default', '-p', 'module=entry@ohosTest', '-p', 'buildMode=debug', 'assembleHap', '--no-daemon')
    }
  } finally { Pop-Location }
  Write-Output "OHOS_BUILD_PASS evidence=$run"
} finally {
  foreach ($name in $envNames) { [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], 'Process') }
}
