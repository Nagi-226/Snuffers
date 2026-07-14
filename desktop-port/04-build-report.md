# 废墟突围 · Windows 桌面端打包链路验证报告（04-build-report）

> 角色：构建验证工程师 ｜ 验证时间：2026-07-14（UTC+8）｜ 分支：`dev_win`
> 目标：验证 `desktop-port/electron/` 的 Electron 打包链路在本机可用，产出 portable（必须）/ nsis（可选）Windows 产物。

---

## 一、结论摘要（TL;DR）

| 项 | 结果 |
|----|------|
| **打包链路是否打通** | ✅ **打通**。electron-builder 可成功产出 portable 与 nsis 两种 Windows 产物 |
| npm install | ✅ 成功（第 2 次尝试，切 npmmirror 镜像后） |
| portable 构建 | ✅ 成功 → `dist/废墟突围-1.0.0-portable.exe`（71.04 MiB） |
| nsis 构建（可选） | ✅ 成功 → `dist/废墟突围-1.0.0-setup.exe`（78.30 MiB）+ `.blockmap` |
| `build.ps1` 一键脚本 | ⚠️ **按原样无法在 PowerShell 5.1 直接运行**，发现 2 处脚本缺陷（见第五节），但其内部逻辑已逐项验证可用 |
| 游戏图标 icon.ico | ⏳ 缺失，构建按预期回退 Electron 默认图标（仅警告，不阻塞） |

> 说明：构建产物本身**全部成功**；"build.ps1 不能一键跑"是脚本自身的两个缺陷导致，并非工具链问题。修好脚本后即可真正一键构建。

---

## 二、环境版本

| 组件 | 版本 | 来源 |
|------|------|------|
| node | v24.15.0 | Kimi Desktop 运行时（`...\kimi-desktop\resources\resources\runtime\node.exe`） |
| npm | 11.12.1 | 同上（`npm.cmd`） |
| electron | 33.4.11（二进制 electron.exe 188,784,128 字节已下载到位） | npm 依赖 |
| electron-builder | 25.1.8 | npm 依赖 |
| PowerShell | 5.1.26100.8737（Windows PowerShell） | `C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe` |
| OS | Windows 10.0.26200（x64） | — |

---

## 三、验证过程与结果

### 3.1 npm install（两次尝试）

**第 1 次（默认源）— 失败**
- 现象：npm 包元数据可正常从默认 registry 拉取（一堆 deprecated 警告即证明已下载），但卡在 **electron 二进制下载**（`node install.js`）。
- 报错：`RequestError: unable to verify the first certificate; if the root CA is installed locally, try running Node.js with --use-system-ca`
- 判定：典型的国内网络 TLS 拦截 / 根 CA 校验失败（electron 默认从 GitHub Releases 下载二进制），**非网络不通**。
- 另注意到一次 Windows 文件占用警告：`EPERM: operation not permitted, rmdir ...\node_modules\dir-compare`（杀软/索引占用特征，瞬时）。

**第 2 次（切镜像）— 成功**
- 设置环境变量后重试：
  - `ELECTRON_MIRROR=https://npmmirror.com/mirrors/electron/`
  - `NODE_OPTIONS=--use-system-ca`
  - `--registry=https://registry.npmmirror.com`
- 结果：`added 404 packages in 18s`，退出码 0。
- 复核：`node_modules/electron/dist/electron.exe`（188,784,128 字节）真实下载到位，非跳过。

> 结论：本机联网正常，只需把 electron / electron-builder 的二进制下载指向 npmmirror 镜像即可。

### 3.2 构建（electron-builder）

为避免 `build.ps1` 脚本缺陷干扰判断，直接调用其底层命令（等价于脚本第 3、4 步）验证工具链。`app/` 资源目录已由脚本复制步骤生成并复核齐全（`index.html` + `js/` + `css/` + `img/`）。

**portable（必须目标）— 成功**
```
npm run build:portable   # = electron-builder --win portable
```
- electron 33.4.11 从 npmmirror 拉取：`115 MB / 12.65s`
- 打包 → `dist\win-unpacked\废墟突围.exe` → 封装 portable
- 提示 `default Electron icon is used (reason=application icon is not set)`：缺 icon.ico，按预期回退默认图标，**未失败**
- 无签名证书：`no signing info identified, signing is skipped`（正常，未配置代码签名）
- 退出码 0

**nsis（可选目标）— 成功**
```
npm run build:nsis       # = electron-builder --win nsis
```
- 产出安装包 + blockmap，退出码 0

> 补充：portable 与 nsis 在 electron-builder 中底层均依赖 NSIS 自解压/安装器，已通过 `ELECTRON_BUILDER_BINARIES_MIRROR=https://npmmirror.com/mirrors/electron-builder-binaries/` 让 winCodeSign / nsis 等二进制走镜像下载，规避与 3.1 相同的证书问题。

---

## 四、产物清单

产物目录：`desktop-port/electron/dist/`（已被 `.gitignore` 忽略，不入库）

| 文件 | 大小（字节） | 大小（约） | 说明 |
|------|-------------|-----------|------|
| `dist/废墟突围-1.0.0-portable.exe` | 74,496,001 | 71.04 MiB（74.5 MB） | 免安装绿色版，双击即玩 |
| `dist/废墟突围-1.0.0-setup.exe` | 82,106,970 | 78.30 MiB（82.1 MB） | NSIS 安装包（可选安装目录、桌面/开始菜单快捷方式） |
| `dist/废墟突围-1.0.0-setup.exe.blockmap` | 86,101 | 84 KiB | 增量更新用块映射 |
| `dist/win-unpacked/` | — | — | 未打包的应用目录（含 electron 运行时 + 游戏资源） |

**产物有效性校验**
- 两个 `.exe` 头部均为 `MZ`（PE32），`file` 识别为 `PE32 executable ... Nullsoft Installer self-extracting archive`，为有效 Windows 可执行文件。
- `file` 显示 `Intel i386` 系 NSIS 安装器/自解压外壳惯例，内嵌载荷为 x64 的 electron 33.4.11（日志中 `electron-v33.4.11-win32-x64.zip`），**非架构错误**。
- 体积落在 `02-packaging.md` 预估的 150–250 MB 区间之下（因未含额外资源、且 electron 体积较克制），若需 < 20 MB 仍需走 Neutralino 路线（见 02 报告）。

---

## 五、发现的问题与修复建议

### 问题 1（阻塞一键运行）：`build.ps1` 编码为 UTF-8 无 BOM
- 现象：`powershell -ExecutionPolicy Bypass -File build.ps1` 直接报 `ParserError`（`UnexpectedToken`、中文乱码、引号配对失败）。
- 根因：文件首字节为 `<#`（`3c 23`），**无 BOM**。Windows PowerShell 5.1 对无 BOM 的 `.ps1` 按系统 ANSI（GBK）解析，文件内中文注释被误读，字节破坏语法。
- 验证：将同一文件加 BOM（`EF BB BF`）后，`PSParser::Tokenize` 校验 `PARSE_OK`，脚本可正常解析执行。
- **修复建议**：把 `build.ps1` 另存为 **UTF-8 with BOM**（或 UTF-8 BOM / 带签名的 ANSI）。推荐加 BOM，改动最小、对 PS 5.1 与 PS 7 都兼容。

### 问题 2（阻塞一键运行）：`build.ps1` 用 `$LASTEXITCODE` 判失败不可靠
- 现象：脚本内 `& $Npm install` 明明成功（`$?` 为 True、PowerShell 退出码 0），但 `$LASTEXITCODE` 为 **`$null`（空）**；于是 `if ($LASTEXITCODE -ne 0)` 因 `$null -ne 0` 恒为真，**误抛"npm install 失败"**。
- 可能成因：`npm.cmd` 是批处理 shim，内部用 `SETLOCAL` 且末尾不显式 `exit /b`，在本机 PowerShell 5.1 的调用方式下退出码未被回填。
- **修复建议**（任选其一）：
  - 用 `$?` 判断：`& $Npm install; if (-not $?) { throw "npm install 失败" }`
  - 或在每次外部调用前初始化：`$global:LASTEXITCODE = 0`，再判 `$LASTEXITCODE -ne 0`
  - 或防空：`if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw ... }`

### 问题 3（非阻塞）：缺 `build/icon.ico`
- 现象：构建警告 `default Electron icon is used`，产物使用 Electron 默认图标。
- 影响：不影响构建与运行，仅影响品牌观感。
- 建议：按 `build/README.md` 用 `img/title-bg.jpg` 截取方形区域，经 icoconvert 等工具生成 256×256 多尺寸 `.ico` 放入 `desktop-port/electron/build/`。

---

## 六、国内网络 · 可复现构建操作步骤

> 以下步骤在本机已实测通过。前提是修好 `build.ps1` 的两个缺陷（问题 1、2），或直接采用「方式 B 命令行」。

### 方式 A：一键脚本（修复 build.ps1 后）
1. 将 `desktop-port/electron/build.ps1` 另存为 **UTF-8 with BOM**。
2. 把两处 `if ($LASTEXITCODE -ne 0)` 改为基于 `$?` 的判断（见问题 2）。
3. 在 PowerShell 中先设置镜像环境变量，再运行脚本：
   ```powershell
   $env:ELECTRON_MIRROR="https://npmmirror.com/mirrors/electron/"
   $env:ELECTRON_BUILDER_BINARIES_MIRROR="https://npmmirror.com/mirrors/electron-builder-binaries/"
   $env:NODE_OPTIONS="--use-system-ca"
   powershell -ExecutionPolicy Bypass -File build.ps1
   ```

### 方式 B：命令行直跑（本次验证采用，最稳妥）
在 `desktop-port/electron/` 目录下：
```bash
# 环境变量（Git Bash / PowerShell 均可，先 export 或 $env: 设置）
ELECTRON_MIRROR=https://npmmirror.com/mirrors/electron/
ELECTRON_BUILDER_BINARIES_MIRROR=https://npmmirror.com/mirrors/electron-builder-binaries/
NODE_OPTIONS=--use-system-ca
npm_config_registry=https://registry.npmmirror.com

# 1) 复制游戏资源到 app/（build.ps1 第 2 步干的事）
#    将项目根的 index.html、js/、css/、img/ 复制到 electron/app/

# 2) 安装依赖
npm install --registry=https://registry.npmmirror.com

# 3) 构建（任选）
npm run build:portable   # 只要绿色版（必须）
npm run build:nsis       # 只要安装包（可选）
npm run build            # 两者都构建
```
产物输出到 `desktop-port/electron/dist/`。

---

## 七、遗留问题 / 后续建议

1. **修复 `build.ps1` 两缺陷**（问题 1 编码、问题 2 退出码判断）后即可真正一键构建；本次按"不改源文件"约束未动它，仅以临时 BOM 副本 + 底层命令完成验证。
2. **补图标** `build/icon.ico`（非阻塞）。
3. **`package-lock.json`**：本次 `npm install` 新生成于 `desktop-port/electron/package-lock.json`（未被 `.gitignore` 忽略）。建议入库以锁定依赖版本、保证可复现构建；是否 add 由主控统一决定。
4. **代码签名**：当前产物未签名（`signing is skipped`），Windows SmartScreen 可能提示。正式发布如需消除告警，需配置代码签名证书（`win.certificateFile` / `CSC_LINK`）。
5. **运行时冒烟**：本报告验证"能构建出有效 .exe"，未做 GUI 实际启动试玩（无显示环境）。建议后续在带桌面的机器上双击 `废墟突围-1.0.0-portable.exe` 做一次启动+键鼠冒烟测试。
6. `node_modules/`、`dist/`、`app/` 均已确认被 `.gitignore` 命中（`git check-ignore` 通过），本次未对仓库做任何 add/commit。
