function Resolve-OhosTaskTarget {
    param([string]$Serial, [int]$ExpectedProcessId, [object]$ProcessRecord, [object[]]$Listeners)
    if ($Serial -notmatch '^127\.0\.0\.1:(\d+)$' -or $ExpectedProcessId -le 0) {
        throw 'An explicit local task emulator process is required.'
    }
    $port = [int]$Matches[1]
    if ($null -eq $ProcessRecord -or $ProcessRecord.ProcessId -ne $ExpectedProcessId -or
        $ProcessRecord.Name -ne 'Emulator.exe') { throw 'Task emulator process identity does not match.' }
    $match = [regex]::Match($ProcessRecord.CommandLine, '(?:^|\s)-hvd\s+(?:"([^"]+)"|(\S+))')
    if (-not $match.Success) { throw 'Task emulator HVD name is missing.' }
    $hvd = if ($match.Groups[1].Success) { $match.Groups[1].Value } else { $match.Groups[2].Value }
    if ($hvd -notin @('FlyNESFlutterG1', 'FlyNESUpgrade212')) {
        throw 'Only the named FlyNES task HVDs may use the explicit target override.'
    }
    $owned = @($Listeners | Where-Object {
        $_.LocalPort -eq $port -and $_.LocalAddress -eq '127.0.0.1' -and
        $_.OwningProcess -eq $ExpectedProcessId
    })
    if ($owned.Count -ne 1) { throw 'HDC port is not owned by the verified task emulator.' }
    return [pscustomobject]@{ serial=$Serial; processId=$ExpectedProcessId; hvd=$hvd;
        commandLine=$ProcessRecord.CommandLine; localPort=$port }
}
