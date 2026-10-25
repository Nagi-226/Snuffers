# Poly Haven CC0 家具下载器：per-asset 解析 files API，取 1k gltf 套件
# (.gltf + .bin + include 贴图) 存入 godot/assets/models/fur_<type>/。
$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$map = @{
    "painted_wooden_sofa"      = "fur_sofa"
    "painted_wooden_table"     = "fur_table"
    "painted_wooden_chair_02"  = "fur_chair"
    "painted_wooden_nightstand"= "fur_nightstand"
    "painted_wooden_shelves"   = "fur_shelf"
    "painted_wooden_cabinet"   = "fur_tv_stand"
}
$base = "E:\Github Project\Nagi_Games\Snuffers\godot\assets\models"
foreach ($pair in $map.GetEnumerator()) {
    $asset = $pair.Key; $name = $pair.Value
    $dir = Join-Path $base $name
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $meta = Invoke-RestMethod -Uri "https://api.polyhaven.com/files/$asset" -TimeoutSec 40
    $g = $meta.gltf."1k".gltf
    if ($null -eq $g) { Write-Output "NO_1K $asset"; continue }
    Invoke-WebRequest -Uri $g.url -OutFile (Join-Path $dir "$name.gltf") -TimeoutSec 120
    foreach ($inc in $g.include.PSObject.Properties) {
        $rel = $inc.Name -replace '/', '\'
        $dest = Join-Path $dir $rel
        $destDir = Split-Path $dest -Parent
        if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Force -Path $destDir | Out-Null }
        Invoke-WebRequest -Uri $inc.Value.url -OutFile $dest -TimeoutSec 180
    }
    $sz = (Get-ChildItem $dir | Measure-Object -Property Length -Sum).Sum / 1MB
    Write-Output ("OK {0} -> {1}  {2:N1}MB {3} files" -f $asset, $name, $sz, (Get-ChildItem $dir).Count)
}
