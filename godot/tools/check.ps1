#Requires -Version 5.1
<#
.SYNOPSIS
    L1 validation chain for the Snuffers Godot spike.
.DESCRIPTION
    Steps:
      a) godot --headless --import            refresh the import cache
      b) -s tests/check_scripts.gd -- <gds>   compile-check every .gd under godot/
                                              (addons/ and .godot/ excluded);
                                              harness replaces --check-only,
                                              which false-reports autoload
                                              member access in headless mode
      c) godot --headless --quit              main scene boot smoke
      d) godot -s res://tests/smoke_contracts.gd   contract assertions
      e) godot --headless --quit <scene>      per-scene instantiation smoke
      f) godot -s res://tests/smoke_scenes.gd scene node assertions
                                              (Sprint 2 scaffold; undelivered
                                              W2/W3 cases report SKIP)
    Prints "L1 PASS" and exits 0 when every step is green.
    Prints "L1 FAIL" plus failure details and exits 1 otherwise.
.NOTES
    Run serially: concurrent godot --import instances fight over the
    .godot cache lock. Pure ASCII on purpose - avoids console encoding traps.
    Godot_v4.6.2-stable_win64.exe is a GUI-subsystem binary: PowerShell's &
    operator launches it asynchronously and never captures output or exit
    code, so this script drives it via System.Diagnostics.Process.
#>

$ErrorActionPreference = 'Continue'
$GodotExe = 'D:\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64.exe'

# Resolve the godot/ project root from this script's location (tools/).
$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectDir = Split-Path -Parent $ScriptDir

$failures = New-Object System.Collections.Generic.List[string]

function Add-Failure([string]$Label, [string]$Detail) {
    $script:failures.Add($Label)
    if ($Detail) { $script:failures.Add($Detail) }
    Write-Host "FAIL  $Label" -ForegroundColor Red
}

function Quote-Arg([string]$Arg) {
    # Wrap whitespace-bearing args (e.g. the project path) in double quotes.
    if ($Arg -match '\s') { return '"' + $Arg + '"' }
    return $Arg
}

function Invoke-Godot([string]$Label, [string[]]$CmdArgs) {
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
    $code = $proc.ExitCode
    $tail = (($outTask.Result + "`n" + $errTask.Result) -split "`r?`n" |
        Where-Object { $_ -ne '' } | Select-Object -Last 30) -join "`n"
    $proc.Dispose()

    if ($code -ne 0) {
        Add-Failure $Label ("exit=" + $code + "`n" + $tail)
        return $false
    }
    Write-Host "ok    $Label" -ForegroundColor Green
    return $true
}

Write-Host '== L1 validation chain =='
Write-Host "engine : $GodotExe"
Write-Host "project: $ProjectDir"

if (-not (Test-Path $GodotExe)) {
    Write-Host "L1 FAIL: Godot executable not found: $GodotExe" -ForegroundColor Red
    exit 1
}

# (a) refresh the import cache
Invoke-Godot 'import cache refresh' @('--headless', '--path', $ProjectDir, '--import') | Out-Null

# (b) per-script compile check (exclude addons/ and .godot/)
# NOTE: `godot --check-only --script` cannot resolve autoload MEMBER access
# in headless mode and false-reports "Identifier not found" on correct
# scripts (Events.* / GameConfig.<var> / GameState.*). tests/check_scripts.gd
# recreates the autoload nodes and force-recompiles each script instead;
# same per-file PASS/FAIL semantics, details in the failure output.
$scripts = Get-ChildItem -Path $ProjectDir -Recurse -Filter '*.gd' -File |
    Where-Object { $_.FullName -notmatch '[\\/](addons|\.godot)[\\/]' }
Write-Host ("found {0} script(s)" -f $scripts.Count)
$scriptArgs = @('--headless', '--path', $ProjectDir, '-s', 'res://tests/check_scripts.gd', '--')
foreach ($gd in $scripts) {
    $scriptArgs += ('res://' + $gd.FullName.Substring($ProjectDir.Length + 1).Replace('\', '/'))
}
Invoke-Godot ("per-script compile check ({0} scripts)" -f $scripts.Count) $scriptArgs | Out-Null

# (c) main scene boot smoke (main scene from project.godot)
Invoke-Godot 'main scene boot smoke' @('--headless', '--path', $ProjectDir, '--quit') | Out-Null

# (d) contract assertions
Invoke-Godot 'contract assertions (tests/smoke_contracts.gd)' @('--headless', '--path', $ProjectDir, '-s', 'res://tests/smoke_contracts.gd') | Out-Null

# (e) per-scene instantiation smoke
$scenesDir = Join-Path $ProjectDir 'scenes'
$scenes = @()
if (Test-Path $scenesDir) {
    $scenes = Get-ChildItem -Path $scenesDir -Recurse -Filter '*.tscn' -File
}
Write-Host ("found {0} scene(s)" -f $scenes.Count)
foreach ($sc in $scenes) {
    $resPath = 'res://' + $sc.FullName.Substring($ProjectDir.Length + 1).Replace('\', '/')
    Invoke-Godot "scene smoke $resPath" @('--headless', '--path', $ProjectDir, '--quit', $resPath) | Out-Null
}

# (f) scene node assertions (Sprint 2 scaffold; W2/W3 placeholder cases SKIP
#     until their scenes land, so the chain stays green during parallel work)
Invoke-Godot 'scene node assertions (tests/smoke_scenes.gd)' @('--headless', '--path', $ProjectDir, '-s', 'res://tests/smoke_scenes.gd') | Out-Null

Write-Host ''
if ($failures.Count -gt 0) {
    Write-Host '== L1 FAIL ==' -ForegroundColor Red
    foreach ($f in $failures) { Write-Host $f }
    exit 1
}
Write-Host '== L1 PASS ==' -ForegroundColor Green
exit 0
