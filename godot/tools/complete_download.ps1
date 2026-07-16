# Day 0 ops: finalize BITS job for Godot export templates
Get-BitsTransfer | Where-Object { $_.DisplayName -eq 'GodotTemplates462' } | Complete-BitsTransfer
Get-Item 'D:\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_export_templates.tpz' |
  Select-Object FullName, @{N='MB'; E={[math]::Round($_.Length/1MB,1)}}
