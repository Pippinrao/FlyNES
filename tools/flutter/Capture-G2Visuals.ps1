param([string]$FlutterCommand = 'flutter')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$flutterPath = (Get-Command $FlutterCommand -ErrorAction Stop).Source
$sdk = (& $flutterPath --version --machine | Out-String | ConvertFrom-Json)
if ($LASTEXITCODE -ne 0) { throw 'Unable to identify screenshot SDK.' }
$fonts = [ordered]@{}
foreach ($name in @('Roboto-Regular.ttf', 'NotoSansCJK-Regular.ttc', 'MaterialIcons-Regular.otf')) {
    $font = Join-Path $repoRoot ".artifacts/flutter-g2/fonts/$name"
    if (-not (Test-Path -LiteralPath $font)) { throw "Missing frozen font: $name" }
    $fonts[$name] = (Get-FileHash -LiteralPath $font -Algorithm SHA256).Hash
}
$environment = [ordered]@{
    sdk = [ordered]@{ framework = $sdk.frameworkRevision; engine = $sdk.engineRevision; dart = $sdk.dartSdkVersion }
    fonts = $fonts
    surface = 'flutter-tester; devicePixelRatio=1; controlled clock; no system keyboard pixels'
    platform = [System.Environment]::OSVersion.VersionString
}
Push-Location (Join-Path $repoRoot 'ui/flutter')
try {
    foreach ($runner in @('g2_visual_capture.dart', 'g2_animation_capture.dart', 'g2_state_capture.dart', 'g2_pseudo_capture.dart', 'g2_extended_state_capture.dart')) {
        & $flutterPath test "verification/$runner" --reporter expanded
        if ($LASTEXITCODE -ne 0) { throw "Screenshot assertions failed: $runner" }
    }
    foreach ($folder in @('visual-actual', 'animation-actual', 'state-actual', 'pseudo-actual', 'extended-state-actual')) {
        $environment | ConvertTo-Json -Depth 5 | Set-Content -Encoding utf8 (Join-Path $repoRoot ".artifacts/flutter-g2/$folder/environment.json")
    }
} finally { Pop-Location }
# Deliberately no golden update: actual PNGs, geometry and semantics require review.
