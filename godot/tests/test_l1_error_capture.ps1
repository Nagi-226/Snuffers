#Requires -Version 5.1
param([string]$CheckScript = (Join-Path (Split-Path -Parent $PSScriptRoot) 'tools/check.ps1'))

$ErrorActionPreference = 'Stop'
$taskTokens = $null
$taskParseErrors = $null
$taskAst = [System.Management.Automation.Language.Parser]::ParseFile($CheckScript, [ref]$taskTokens, [ref]$taskParseErrors)
if ($taskParseErrors.Count) { throw 'L1 check script does not parse' }
$taskNames = @('Add-Failure', 'Quote-Arg', 'Invoke-Godot')
$taskFunctions = $taskAst.FindAll({ param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -in $taskNames
}, $true)
if ($taskFunctions.Count -ne 3) { throw 'L1 capture functions were not found' }
foreach ($taskFunction in $taskFunctions) { Invoke-Expression $taskFunction.Extent.Text }

# A real child process exercises the gate without starting Godot or sharing its cache.
$GodotExe = (Get-Command powershell.exe).Source
$LogPath = Join-Path (Split-Path -Parent $PSScriptRoot) '.godot/l1_error_capture_test.log'
[void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $LogPath))
$failures = New-Object System.Collections.Generic.List[string]
$taskAssertions = 0
$taskFailures = 0

function Assert-Result([bool]$Condition, [string]$Label) {
    $script:taskAssertions++
    if ($Condition) { Write-Output "PASS: $Label" }
    else { $script:taskFailures++; Write-Output "FAIL: $Label" }
}

foreach ($taskPrefix in @('SCRIPT ERROR:', 'ERROR:')) {
    $failures.Clear()
    [System.IO.File]::WriteAllText($LogPath, '')
    $taskCommand = "[Console]::WriteLine('CAPTURED_STDOUT'); [Console]::Error.WriteLine('$taskPrefix expected negative control'); exit 0"
    $taskOk = Invoke-Godot "expected $taskPrefix negative control" @('-NoProfile', '-Command', $taskCommand) 6>$null
    Assert-Result (-not $taskOk -and $failures.Count -gt 0) "$taskPrefix with exit zero fails the L1 gate"
    $taskLog = [System.IO.File]::ReadAllText($LogPath)
    Assert-Result ($taskLog.Contains('CAPTURED_STDOUT') -and $taskLog.Contains($taskPrefix)) 'full stdout and stderr are preserved'
}

$failures.Clear()
$taskOk = Invoke-Godot 'warning-only positive control' @('-NoProfile', '-Command', "[Console]::Error.WriteLine('WARNING: expected control'); exit 0") 6>$null
Assert-Result ($taskOk -and $failures.Count -eq 0) 'a warning alone does not fail the gate'

$failures.Clear()
$taskOk = Invoke-Godot 'expected nonzero negative control' @('-NoProfile', '-Command', 'exit 2') 6>$null
Assert-Result (-not $taskOk -and $failures.Count -gt 0) 'a nonzero exit still fails the gate'

$failures.Clear()
$taskOk = Invoke-Godot 'successful positive control' @('-NoProfile', '-Command', "[Console]::WriteLine('SUCCESS'); exit 0") 6>$null
Assert-Result ($taskOk -and $failures.Count -eq 0) 'a successful child still passes the gate'

Write-Output "L1_ERROR_CAPTURE assertions=$taskAssertions failures=$taskFailures"
exit ([int]($taskFailures -gt 0))
