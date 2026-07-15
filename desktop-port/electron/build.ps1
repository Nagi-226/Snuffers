<#
  废墟突围 - Electron 一键构建脚本
  用法：右键“使用 PowerShell 运行”，或执行：
    powershell -ExecutionPolicy Bypass -File build.ps1

  流程：
    1. 校验 node / npm-cli（使用 Kimi Desktop 自带运行时绝对路径）
       ※ 直接调用 node + npm-cli.js / electron-builder cli.js，绕开 npm.cmd
         （npm.cmd 在部分非交互环境下会静默不执行且无退出码，导致“假成功”）
    2. 把项目根目录的 index.html / js/ / css/ / img/ / audio/ 复制到 electron/app/
       （electron-builder 只打包应用目录内文件，且游戏源文件零修改）
    3. npm install（首次构建需联网下载 electron / electron-builder）
    4. electron-builder 构建 portable + nsis → 产物输出到 electron/dist/
    5. 时间戳自检：若 exe 早于 app/index.html 则判定构建未生效并报错
#>

$ErrorActionPreference = 'Stop'

# ---------- 0. 路径与环境 ----------
$NpmDir  = 'C:\Users\FJL03\AppData\Local\Programs\kimi-desktop\resources\resources\runtime'
$Node    = Join-Path $NpmDir 'node.exe'
$NpmCli  = Join-Path $NpmDir 'node_modules\npm\bin\npm-cli.js'
$Builder = Join-Path $PSScriptRoot 'node_modules\electron-builder\cli.js'
$Root    = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path   # 项目根目录
$AppDir  = Join-Path $PSScriptRoot 'app'
$DistDir = Join-Path $PSScriptRoot 'dist'

foreach ($p in @($Node, $NpmCli)) {
  if (-not (Test-Path $p)) {
    Write-Error "未找到运行时文件：$p`n请确认 Kimi Desktop 运行时路径，或修改脚本顶部 `$NpmDir。"
    exit 1
  }
}

# 让 npm / electron-builder 的子进程能找到同目录的 node.exe
$env:PATH = "$NpmDir;$env:PATH"

Write-Host "==> node / npm 版本：" -ForegroundColor Cyan
& $Node --version
& $Node $NpmCli --version
if (-not $?) { throw "npm-cli 不可用" }

# ---------- 1. 校验游戏源文件 ----------
$required = @('index.html', 'js', 'css', 'img', 'audio')
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
foreach ($dir in @('js', 'css', 'img', 'audio')) {
  Copy-Item (Join-Path $Root $dir) (Join-Path $AppDir $dir) -Recurse
}

# ---------- 3. 安装依赖 ----------
Write-Host "==> npm install（首次较慢，需联网）..." -ForegroundColor Cyan
Push-Location $PSScriptRoot
try {
  & $Node $NpmCli install
  # 本环境子进程退出码可能为 $null（$null -ne 0 在 PS 中恒真，不可用作失败判断）
  if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw "npm install 失败，退出码 $LASTEXITCODE" }
  if (-not (Test-Path $Builder)) { throw "npm install 未生效：未找到 $Builder" }

  # ---------- 4. 构建 ----------
  Write-Host "==> electron-builder 构建 Windows 产物（portable + nsis）..." -ForegroundColor Cyan
  & $Node $Builder
  if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw "electron-builder 构建失败，退出码 $LASTEXITCODE" }
}
finally {
  Pop-Location
}

# ---------- 5. 时间戳自检（防“假成功”） ----------
$appMtime = (Get-Item (Join-Path $AppDir 'index.html')).LastWriteTime
$exes = Get-ChildItem $DistDir -Filter *.exe -ErrorAction SilentlyContinue
if (-not $exes) { throw "dist/ 下未找到任何 .exe 产物" }
foreach ($exe in $exes) {
  if ($exe.LastWriteTime -lt $appMtime) {
    throw "产物 $($exe.Name) 早于 app/ 资源快照时间，构建未生效，请检查上方 electron-builder 输出"
  }
}

# ---------- 6. 完成 ----------
Write-Host ""
Write-Host "构建完成！产物位于：" -ForegroundColor Green
Write-Host "  $DistDir" -ForegroundColor Green
$exes | ForEach-Object { Write-Host ("  - {0}  ({1:N1} MB, {2:yyyy-MM-dd HH:mm})" -f $_.Name, ($_.Length / 1MB), $_.LastWriteTime) }
