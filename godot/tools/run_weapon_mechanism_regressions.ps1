#Requires -Version 5.1
param(
 [string]$GodotExe = 'D:\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64.exe',
 [string]$LogDirectory = '',
 [string[]]$Only = @()
)
$ErrorActionPreference = 'Stop'
$taskProject = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (-not $LogDirectory) { $LogDirectory = Join-Path (Split-Path $taskProject -Parent) '.kimi-tmp\nov11_g17_mpx\mechanism_regressions' }
[void][IO.Directory]::CreateDirectory($LogDirectory)
$taskLegacy = @(
 'test_ads_switch', 'test_conventional_9x19', 'test_em120r_rear_reload',
 'test_ec86_capacity', 'test_ec57_capacity', 'test_ec120_missile',
 'test_bullet_marks_render', 'test_black_pistol_integration', 'test_explosion_surface_marks',
 'test_em_final_platforms', 'test_em57s2_ads', 'test_em86_platforms',
 'test_hip_framing_shared_ads', 'test_heavy_platforms', 'test_long_guns',
 'test_em_new_platforms', 'test_native_long_gun_rig', 'test_native_pistol_ads_idle',
 'test_native_pistol_pose', 'test_native_pistol_stillness', 'test_native_special_reload',
 'test_new_weapon_platforms', 'test_player_ads_magazine', 'test_reload_magazine_contact',
 'test_spas12', 'test_reload_magazine_platforms', 'test_spas12_visibility',
 'test_viewmodel_wall_clearance', 'test_weapons_range', 'test_weapon_reload',
 'test_weapon_presentation', 'test_weapon_selection'
)
$taskUi = @('test_full_scope_weapon_hud', 'test_nano_modes', 'test_street_ammo_pickups', 'test_explosion_surface_marks_render', 'test_asset_credits')
$taskRows = @()
foreach ($taskName in $taskLegacy + $taskUi) { $taskRows += [pscustomobject]@{ Name=$taskName; Script=('res://tests/' + $taskName + '.gd'); Native=$true } }
foreach ($taskName in @('probe_conventional_9x19', 'probe_conventional_feedback', 'probe_reticle_auto_feedback')) { $taskRows += [pscustomobject]@{ Name=$taskName; Script=('res://tools/' + $taskName + '.gd'); Native=$true } }
$taskRows += [pscustomobject]@{ Name='smoke_contracts'; Script='res://tests/smoke_contracts.gd'; Native=$false }
$taskRows | Export-Csv -NoTypeInformation -Encoding UTF8 -LiteralPath (Join-Path $LogDirectory 'manifest.csv')
foreach ($taskName in $Only) { if ($taskName -notin $taskRows.Name) { throw ('Unknown regression: ' + $taskName) } }
if ($Only.Count -gt 0) { $taskRows = @($taskRows | Where-Object { $_.Name -in $Only }) }
$taskResults = @()
foreach ($taskRow in $taskRows) {
 $taskScriptFile = Join-Path $taskProject $taskRow.Script.Substring(6)
 if (-not (Test-Path -LiteralPath $taskScriptFile)) { throw ('Missing regression script: ' + $taskScriptFile) }
 $taskInfo = New-Object System.Diagnostics.ProcessStartInfo
 $taskInfo.FileName = $GodotExe
 $taskMode = if ($taskRow.Native) { '--position -4000,-4000 --resolution 1600x900' } else { '--headless' }
 $taskInfo.Arguments = $taskMode + ' --path "' + $taskProject + '" --max-fps 60 -s "' + $taskRow.Script + '"'
 $taskInfo.UseShellExecute = $false
 $taskInfo.RedirectStandardOutput = $true
 $taskInfo.RedirectStandardError = $true
 $taskInfo.CreateNoWindow = $true
 $taskProcess = New-Object System.Diagnostics.Process
 $taskProcess.StartInfo = $taskInfo
 [void]$taskProcess.Start()
 $taskOut = $taskProcess.StandardOutput.ReadToEndAsync()
 $taskErr = $taskProcess.StandardError.ReadToEndAsync()
 $taskTimeout = -not $taskProcess.WaitForExit(300000)
 if ($taskTimeout) { $taskProcess.Kill(); $taskProcess.WaitForExit() }
 $taskCode = $taskProcess.ExitCode
 $taskOutput = $taskOut.Result + "`n" + $taskErr.Result
 $taskLog = Join-Path $LogDirectory ($taskRow.Name + '.log')
 [IO.File]::WriteAllText($taskLog, $taskOutput, [Text.UTF8Encoding]::new($false))
 $taskErrors = [regex]::Matches($taskOutput, '(?m)^(ERROR:|SCRIPT ERROR:|FAIL[: ])').Count
 $taskWarnings = [regex]::Matches($taskOutput, '(?m)^WARNING:').Count
 $taskPassed = -not $taskTimeout -and $taskCode -eq 0 -and $taskErrors -eq 0
 $taskResults += [pscustomobject]@{ Test=$taskRow.Name; Native=$taskRow.Native; ExitCode=$taskCode; TimedOut=$taskTimeout; ErrorCount=$taskErrors; WarningCount=$taskWarnings; Passed=$taskPassed; Log=$taskLog }
 $taskResults | Export-Csv -NoTypeInformation -Encoding UTF8 -LiteralPath (Join-Path $LogDirectory 'results.csv')
 $taskProcess.Dispose()
 Write-Output ('REGRESSION ' + $taskRow.Name + ' exit=' + $taskCode + ' errors=' + $taskErrors + ' warnings=' + $taskWarnings + ' completed=' + $taskResults.Count + '/' + $taskRows.Count)
}
$taskFailed = @($taskResults | Where-Object { -not $_.Passed })
Write-Output ('MECHANISM_REGRESSIONS total=' + $taskResults.Count + ' failures=' + $taskFailed.Count)
if ($taskFailed.Count -gt 0) { exit 1 }
exit 0
