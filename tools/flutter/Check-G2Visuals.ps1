[CmdletBinding()]
param(
    [string]$FlutterCommand = 'flutter',
    [string]$PythonCommand = 'py',
    [string]$OutputDirectory = '.artifacts/flutter-g2/visual-gate'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
Push-Location $repoRoot
try {
    & (Join-Path $PSScriptRoot 'Capture-G2Visuals.ps1') -FlutterCommand $FlutterCommand
    $families = [ordered]@{
        visual = 'visual-actual'
        state = 'state-actual'
        pseudo = 'pseudo-actual'
        extended = 'extended-state-actual'
        animation = 'animation-actual'
    }
    foreach ($family in $families.Keys) {
        $expected = "ui/flutter/verification/goldens/$family"
        $arguments = @()
        if ([IO.Path]::GetFileNameWithoutExtension($PythonCommand) -eq 'py') { $arguments += '-3' }
        $arguments += @('tools/flutter/verify_g2_visuals.py',
            '--actual', ".artifacts/flutter-g2/$($families[$family])",
            '--expected', $expected, '--review', "$expected/review.json",
            '--output', (Join-Path $OutputDirectory $family))
        & $PythonCommand @arguments
        if ($LASTEXITCODE -ne 0) { throw "Reviewed visual fixture mismatch: $family" }
    }
    Write-Output '199 reviewed static fixtures and 81 controlled-clock animation frames passed. Native handoffs require separate evidence.'
} finally { Pop-Location }
