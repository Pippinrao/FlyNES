[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$FlutterSdk,
  [Parameter(Mandatory)][string]$Adb,
  [Parameter(Mandatory)][string]$AndroidSerial
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$destination = Join-Path $repo '.artifacts/flutter-g2/fonts'
$expectedImage = 'Android/sdk_phone64_x86_64/emu64x:15/AE3A.240806.019/12368160:userdebug/test-keys'
$fingerprint = (& $Adb -s $AndroidSerial shell getprop ro.build.fingerprint | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $fingerprint -ne $expectedImage) { throw 'The frozen Android font image does not match.' }
$fonts = @(
  @{ Name='Roboto-Regular.ttf'; Sdk='roboto-regular.ttf'; Sha='79E851404657DAC2106B3D22AD256D47824A9A5765458EDB72C9102A45816D95' },
  @{ Name='MaterialIcons-Regular.otf'; Sdk='materialicons-regular.otf'; Sha='D9865B671A09D683D13A863089D8825E0F61A37696CE5D7D448BC8023AA62453' },
  @{ Name='NotoSansCJK-Regular.ttc'; Sdk=''; Sha='3E7E5AFAAC2C6D872592D76ABEDAC03A51C6F0FC42D11E311FF2816A6C368AFE' }
)
New-Item -ItemType Directory -Path $destination -Force | Out-Null
foreach ($font in $fonts) {
  $target = Join-Path $destination $font.Name
  if (Test-Path -LiteralPath $target) {
    if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $font.Sha) {
      throw "Existing font differs; preserve it and investigate: $($font.Name)"
    }
    continue
  }
  if ($font.Sdk) {
    $source = Join-Path $FlutterSdk "bin/cache/artifacts/material_fonts/$($font.Sdk)"
    if ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne $font.Sha) { throw 'Flutter SDK font differs.' }
    Copy-Item -LiteralPath $source -Destination $target
  } else {
    & $Adb -s $AndroidSerial pull /system/fonts/NotoSansCJK-Regular.ttc $target
    if ($LASTEXITCODE -ne 0) { throw 'Cannot read the frozen system font.' }
  }
  if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $font.Sha) { throw 'Extracted font hash differs.' }
}
Write-Host 'G2 font hashes match; no device settings or application data changed.'
