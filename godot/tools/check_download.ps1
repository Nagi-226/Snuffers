# Day 0 ops: query BITS download progress for Godot export templates
Get-BitsTransfer | Select-Object DisplayName, JobState,
  @{N='MB_Transferred'; E={[math]::Round($_.BytesTransferred/1MB,1)}},
  @{N='MB_Total'; E={if($_.BytesTotal -gt 1PB){'?'}else{[math]::Round($_.BytesTotal/1MB,1)}}} |
  Format-Table -AutoSize
