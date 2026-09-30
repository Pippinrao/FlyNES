$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../OhosTaskTarget.ps1')
$process = [pscustomobject]@{ ProcessId=123; Name='Emulator.exe'; CommandLine='Emulator.exe -hvd FlyNESFlutterG1 -path task' }
$listener = [pscustomobject]@{ LocalPort=5555; LocalAddress='127.0.0.1'; OwningProcess=123 }
$accepted = Resolve-OhosTaskTarget '127.0.0.1:5555' 123 $process @($listener)
if ($accepted.hvd -ne 'FlyNESFlutterG1' -or $accepted.processId -ne 123) { throw 'Valid task HVD rejected.' }
$cases = @(
    @{ Serial='127.0.0.1:5555'; ExpectedProcessId=0; ProcessRecord=$process; Listeners=@($listener) },
    @{ Serial='127.0.0.1:5555'; ExpectedProcessId=124; ProcessRecord=$process; Listeners=@($listener) },
    @{ Serial='127.0.0.1:5555'; ExpectedProcessId=123; ProcessRecord=[pscustomobject]@{ProcessId=123;Name='Emulator.exe';CommandLine='Emulator.exe -hvd UserPhone'}; Listeners=@($listener) },
    @{ Serial='127.0.0.1:5555'; ExpectedProcessId=123; ProcessRecord=[pscustomobject]@{ProcessId=123;Name='Other.exe';CommandLine=$process.CommandLine}; Listeners=@($listener) },
    @{ Serial='127.0.0.1:5557'; ExpectedProcessId=123; ProcessRecord=$process; Listeners=@($listener) },
    @{ Serial='192.168.1.1:5555'; ExpectedProcessId=123; ProcessRecord=$process; Listeners=@($listener) }
)
foreach ($case in $cases) {
    $rejected = $false
    try { $null = Resolve-OhosTaskTarget @case } catch { $rejected = $true }
    if (-not $rejected) { throw "Unsafe target accepted: $($case | ConvertTo-Json -Compress)" }
}
Write-Output '7 task identity checks passed; no device commands executed.'
