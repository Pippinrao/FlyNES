[CmdletBinding()]
param(
  [string] $FlutterSdk = 'E:/workspace/lib/flutter/flutter-ohos-3.41.10-1.0.0',
  [string] $DevEco = 'D:/soft/DevEco Studio',
  [string] $PubCache = 'E:/workspace/lib/flutter/oh-pub',
  [ValidateSet('debug', 'profile', 'release')]
  [string] $Mode = 'debug',
  [switch] $BuildTests
)
$ErrorActionPreference = 'Stop'
if ($BuildTests -and $Mode -ne 'debug') {
  throw 'The current Hypium debug routes require -Mode debug when using -BuildTests.'
}
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
    Invoke-Recorded "har-$Mode" $flutter @('build', 'har', "--$Mode", '--target-platform', 'ohos-arm64,ohos-x64', '--no-pub')
  } finally { Pop-Location }
  $harDestination = Join-Path $repo 'harmony/.artifacts/flutter-har'
  New-Item -ItemType Directory -Path $harDestination -Force | Out-Null
  $harFiles = @(
    @{ Source = "flutter_embedding_$Mode.har"; Name = 'flutter_embedding.har' },
    @{ Source = "arm64_v8a_$Mode.har"; Name = 'arm64_v8a.har' },
    @{ Source = "x86_64_$Mode.har"; Name = 'x86_64.har' },
    @{ Source = 'flutter_module.har'; Name = 'flutter_module.har' }
  )
  $harRecords = @()
  foreach ($har in $harFiles) {
    $source = Join-Path $module "build/ohos/har/$Mode/$($har.Source)"
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Missing $Mode HAR: $source" }
    $destination = Join-Path $harDestination $har.Name
    Copy-Item -LiteralPath $source -Destination $destination -Force
    $harRecords += @{ name = $har.Name; sha256 = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant() }
  }
  # Publish provenance last: an interrupted overwrite fails the hash guard.
  $harManifest = @{ schemaVersion = 1; mode = $Mode; sdkRevision = $revision; files = $harRecords }
  $harManifest | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $harDestination 'manifest.json') -Encoding utf8NoBOM
  $harManifest | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $run 'har-manifest.json') -Encoding utf8NoBOM
  & (Join-Path $repo 'tools/content/sync-builtin-content.ps1') -Root $repo
  if ($LASTEXITCODE -ne 0) { throw 'Content staging failed.' }
  Push-Location (Join-Path $repo 'harmony')
  try {
    Invoke-Recorded 'ohpm-install' $node @($ohpmCli, 'install', '--all')
    Invoke-Recorded "hap-$Mode" $node @($hvigor, '--mode', 'module', '-p', 'product=default', '-p', "buildMode=$Mode", 'assembleHap', '--no-daemon')
    Copy-Item -LiteralPath (Join-Path $repo 'harmony/entry/src/main/resources/rawfile/build-revision.json') -Destination (Join-Path $run 'build-revision.json')
    if ($BuildTests) {
      Invoke-Recorded 'hap-tests' $node @($hvigor, '--mode', 'module', '-p', 'product=default', '-p', 'module=entry@ohosTest', '-p', 'buildMode=debug', 'assembleHap', '--no-daemon')
      Copy-Item -LiteralPath (Join-Path $repo 'harmony/entry/src/main/resources/rawfile/build-revision.json') -Destination (Join-Path $run 'build-revision-tests.json')
    }
  } finally { Pop-Location }
  $packages = Join-Path $run 'packages'
  New-Item -ItemType Directory -Path $packages | Out-Null
  Copy-Item -Path (Join-Path $repo 'harmony/entry/build/default/outputs/default/*.hap') -Destination $packages
  if ($BuildTests) {
    Copy-Item -Path (Join-Path $repo 'harmony/entry/build/default/outputs/ohosTest/*.hap') -Destination $packages
  }
  Get-ChildItem -LiteralPath $packages -Filter '*.hap' | Get-FileHash -Algorithm SHA256 |
    Select-Object Path,Hash | ConvertTo-Json | Set-Content (Join-Path $run 'package-hashes.json')
  Write-Output "OHOS_BUILD_PASS mode=$Mode evidence=$run"
} finally {
  foreach ($name in $envNames) { [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], 'Process') }
}
