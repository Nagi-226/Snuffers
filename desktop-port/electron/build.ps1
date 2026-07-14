<#
  废墟突围 - Electron 一键构建脚本
  用法：双击本文件，或在 PowerShell 中执行：
    powershell -ExecutionPolicy Bypass -File build.ps1

  流程：
    1. 校验 npm（使用 Kimi Desktop 自带的 npm.cmd 绝对路径）
    2. 把项目根目录的 index.html / js/ / css/ / img/ 复制到 electron/app/
       （electron-builder 只打包应用目录内文件，且游戏源文件零修改）
    3. npm install（首次构建需联网下载 electron / electron-builder）
    4. npm run build → 产物输出到 electron/dist/
#>

$ErrorActionPreference = 'Stop'

# ---------- 0. 路径与环境 ----------
$NpmDir  = 'C:\Users\FJL03\AppData\Local\Programs\kimi-desktop\resources\resources\runtime'
$Npm     = Join-Path $NpmDir 'npm.cmd'
$Root    = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path   # 项目根目录
$AppDir  = Join-Path $PSScriptRoot 'app'
$DistDir = Join-Path $PSScriptRoot 'dist'

if (-not (Test-Path $Npm)) {
  Write-Error "未找到 npm.cmd：$Npm`n请确认 Kimi Desktop 运行时路径，或修改脚本顶部 `$NpmDir。"
  exit 1
}

# 让 npm / electron-builder 的子进程能找到同目录的 node.exe
$env:PATH = "$NpmDir;$env:PATH"

Write-Host "==> npm 版本：" -ForegroundColor Cyan
& $Npm --version

# ---------- 1. 校验游戏源文件 ----------
$required = @('index.html', 'js', 'css', 'img')
foreach ($item in $required) {
  if (-not (Test-Path (Join-Path $Root $item))) {
    Write-Error "项目根目录缺少 $item ：$Root"
    exit 1
  }
}

# ---------- 2. 复制游戏资源到 app/ ----------
Write-Host "==> 复制游戏资源到 $AppDir ..." -ForegroundColor Cyan
if (Test-Path $AppDir) { Remove-Item $AppDir -Recurse -Force }
New-Item -ItemType Directory -Path $AppDir | Out-Null

Copy-Item (Join-Path $Root 'index.html') $AppDir
foreach ($dir in @('js', 'css', 'img')) {
  Copy-Item (Join-Path $Root $dir) (Join-Path $AppDir $dir) -Recurse
}

# ---------- 3. 安装依赖 ----------
Write-Host "==> npm install（首次较慢，需联网）..." -ForegroundColor Cyan
Push-Location $PSScriptRoot
try {
  & $Npm install
  if ($LASTEXITCODE -ne 0) { throw "npm install 失败，退出码 $LASTEXITCODE" }

  # ---------- 4. 构建 ----------
  Write-Host "==> electron-builder 构建 Windows 产物..." -ForegroundColor Cyan
  & $Npm run build
  if ($LASTEXITCODE -ne 0) { throw "electron-builder 构建失败，退出码 $LASTEXITCODE" }
}
finally {
  Pop-Location
}

# ---------- 5. 完成 ----------
Write-Host ""
Write-Host "构建完成！产物位于：" -ForegroundColor Green
Write-Host "  $DistDir" -ForegroundColor Green
Get-ChildItem $DistDir -Filter *.exe -ErrorAction SilentlyContinue |
  ForEach-Object { Write-Host ("  - {0}  ({1:N1} MB)" -f $_.Name, ($_.Length / 1MB)) }
