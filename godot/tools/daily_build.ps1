#Requires -Version 5.1
<#
.SYNOPSIS
    Daily build for the Ruins Breakout Godot spike.
.DESCRIPTION
    1) Runs tools/check.ps1 (L1 validation chain). Any red aborts the build
       with a non-zero exit code.
    2) Exports a dated Windows release exe:
         godot --headless --export-release "Windows Desktop" ^
               export/ruins_breakout_spike_yyyyMMdd.exe
    Prints artifact size and wall-clock time on success.
.NOTES
    The export preset name must stay "Windows Desktop" (matches
    export_presets.cfg). Run serially - see check.ps1 notes about the
    .godot cache lock. Pure ASCII on purpose.
    Godot_v4.6.2-stable_win64.exe is a GUI-subsystem binary: PowerShell's &
    operator launches it asynchronously and never captures output or exit
    code, so this script drives it via System.Diagnostics.Process.
#>

$ErrorActionPreference = 'Continue'
$GodotExe = 'D:\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64.exe'

# Resolve the godot/ project root from this script's location (tools/).
$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectDir = Split-Path -Parent $ScriptDir

function Quote-Arg([string]$Arg) {
    # Wrap whitespace-bearing args (e.g. the project path) in double quotes.
    if ($Arg -match '\s') { return '"' + $Arg + '"' }
    return $Arg
}

function Invoke-GodotCapture([string[]]$CmdArgs) {
    # Returns @{ ExitCode = int; Output = string } for a synchronous Godot run.
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $GodotExe
    $psi.Arguments = (($CmdArgs | ForEach-Object { Quote-Arg $_ }) -join ' ')
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    [void]$proc.Start()
    # Drain both pipes asynchronously to avoid buffer-fill deadlocks.
    $outTask = $proc.StandardOutput.ReadToEndAsync()
    $errTask = $proc.StandardError.ReadToEndAsync()
    $proc.WaitForExit()
    $result = @{
        ExitCode = $proc.ExitCode
        Output   = ($outTask.Result + "`n" + $errTask.Result)
    }
    $proc.Dispose()
    return $result
}

$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

# Step 1: L1 gate. check.ps1 sets $LASTEXITCODE.
& (Join-Path $ScriptDir 'check.ps1')
if ($LASTEXITCODE -ne 0) {
    Write-Host 'daily build aborted: L1 chain is red' -ForegroundColor Red
    exit 1
}

# Step 2: export dated release exe.
$dateStamp  = Get-Date -Format 'yyyyMMdd'
$exportDir  = Join-Path $ProjectDir 'export'
New-Item -ItemType Directory -Force -Path $exportDir | Out-Null
$exportPath = Join-Path $exportDir ("ruins_breakout_spike_{0}.exe" -f $dateStamp)

Write-Host "exporting: $exportPath"
$run = Invoke-GodotCapture @('--headless', '--path', $ProjectDir, '--export-release', 'Windows Desktop', $exportPath)
if ($run.ExitCode -ne 0 -or -not (Test-Path $exportPath)) {
    Write-Host 'daily build FAILED: export step failed' -ForegroundColor Red
    (($run.Output -split "`r?`n" | Select-Object -Last 30) -join "`n") | Write-Host
    exit 1
}

$sizeMB = [math]::Round((Get-Item $exportPath).Length / 1MB, 1)
$stopwatch.Stop()
Write-Host ("artifact: {0} ({1} MB)" -f $exportPath, $sizeMB)
Write-Host ("elapsed : {0:mm}m {0:ss}s" -f $stopwatch.Elapsed)
Write-Host 'daily build OK' -ForegroundColor Green
exit 0
