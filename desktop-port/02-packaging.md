# 02 · Windows 桌面端打包方案（Electron）

> 角色：桌面打包工程师 | 输出目录：`desktop-port/electron/`
> **前置声明**：本方案**不修改任何游戏源文件**（`index.html` / `js/` / `css/` / `img/` 保持原样），
> 仅通过「复制资源 → 套壳打包」产出桌面端；且与键鼠适配工作**完全正交**——
> 本骨架只管把游戏装进 .exe，操控层改造（Pointer Lock、键位映射）由适配方案独立进行，
> 二者可在任意顺序落地、互不阻塞。

---

## 一、结论先行

1. **方案选型：Electron**。游戏是纯静态离线单页应用（全部资源相对路径引用），
   Electron 套壳零侵入、构建链成熟，本机已验证 npm 可用（v11.12.1，
   路径 `C:\Users\FJL03\AppData\Local\Programs\kimi-desktop\resources\resources\runtime\npm.cmd`）。
2. **骨架已就绪**：`package.json` / `main.js` / `build.ps1` / `.gitignore` / `build/README.md`
   全部创建完毕，**双击 `build.ps1` 即可一键构建**（首次需联网下载依赖）。
3. **预期产物**：portable 绿色版 + NSIS 安装包各一个，单个约 **150–250 MB**
   （Electron 运行时约 120–200 MB + Three.js/Cannon.js 游戏资源约 5 MB）。
4. **轻量替代**：Neutralino（约 5–15 MB，免 npm，直接下载 neu 二进制）作为
   「小体积优先」场景备选；Tauri 因本机无 Rust/cargo 工具链，**不推荐**。
5. **安全加固**：`nodeIntegration:false` + `contextIsolation:true` + `sandbox:true`
   全开，游戏为纯静态内容无 Node 需求，沙箱不影响运行。

---

## 二、目录结构

```
desktop-port/electron/
├── package.json        # 依赖声明 + electron-builder 构建配置
├── main.js             # Electron 主进程（窗口/权限/全屏/安全）
├── build.ps1           # 一键构建脚本（复制资源 → install → build）
├── .gitignore          # 忽略 node_modules/ dist/ app/
├── build/
│   ├── README.md       # 图标占位说明（icon.ico 规格与来源）
│   └── icon.ico        # 【待补】256×256 应用图标，缺失时自动回退默认图标
├── app/                # 【构建时自动生成】游戏资源副本，不入库
│   ├── index.html
│   ├── js/  css/  img/
└── dist/               # 【构建产物】.exe 输出目录，不入库
```

**为什么复制到 `app/`**：electron-builder 只能打包应用目录（`package.json` 所在目录）
内的文件；直接引用 `../../index.html` 会在打包后路径失效。`build.ps1` 每次构建前
全量刷新 `app/`，保证副本与游戏源码同步且源码零改动。

---

## 三、完整构建步骤

### 方式 A：双击构建（推荐）

1. 在资源管理器中右键 `desktop-port/electron/build.ps1` →「使用 PowerShell 运行」
   （若提示执行策略限制，改在终端执行：
   `powershell -ExecutionPolicy Bypass -File "desktop-port/electron/build.ps1"`）。
2. 脚本自动执行：
   - 校验 npm.cmd（绝对路径，不依赖系统 PATH）；
   - 将项目根目录 `index.html` / `js/` / `css/` / `img/` 复制到 `electron/app/`；
   - `npm install`（**首次约 2–5 分钟**，下载 electron ~200MB 与 electron-builder，
     需联网；后续构建命中缓存很快）；
   - `npm run build`（electron-builder 打 portable + nsis 双产物，约 1–3 分钟）。
3. 结束后终端列出产物路径与体积。

### 方式 B：手动分步（调试时用）

```powershell
$env:PATH = "C:\Users\FJL03\AppData\Local\Programs\kimi-desktop\resources\resources\runtime;$env:PATH"
cd "E:\Github Project\Nagi_Games\Ruins-Breakout\desktop-port\electron"
# 手动复制 app/ 后：
npm.cmd install
npm.cmd run start          # 开发预览：直接开窗运行，不打包
npm.cmd run build:portable # 只打绿色版
npm.cmd run build:nsis     # 只打安装包
```

### 预期产物（`desktop-port/electron/dist/`）

| 文件 | 类型 | 预期体积 |
|---|---|---|
| `废墟突围-1.0.0-portable.exe` | 绿色单文件，双击即玩 | ~150–250 MB |
| `废墟突围-1.0.0-setup.exe` | NSIS 安装包（可选安装目录、桌面快捷方式） | ~150–250 MB |
| `win-unpacked/` | 未压缩目录（构建中间产物，可删） | ~250 MB |

> 体积构成：Chromium + Electron 运行时约 120–200 MB 是大头且不可裁剪；
> 游戏本体（three.min.js 600KB + cannon.min.js 150KB + index.html + 贴图）仅约 5 MB。
> 若对体积敏感，见第五节 Neutralino 方案。

### 图标（可选，不阻塞构建）

未放 `build/icon.ico` 时构建**不会失败**，仅回退 Electron 默认图标。
补图标：准备 256×256 PNG → 转多尺寸 .ico → 存为 `desktop-port/electron/build/icon.ico`，
重新构建即可（详见 `electron/build/README.md`）。

---

## 四、骨架关键设计（main.js）

- **窗口**：1280×720 起步、最小 800×450、隐藏菜单栏（`autoHideMenuBar` + `Menu.setApplicationMenu(null)`）；
- **安全**：`nodeIntegration:false / contextIsolation:true / sandbox:true`，
  游戏纯静态离线、不依赖 Node，沙箱全开无功能损失；
- **pointerLock 放行**：在窗口 session 与 defaultSession 双层注册
  `setPermissionRequestHandler`，`permission === 'pointerLock'` 一律允许，
  其余权限（摄像头/麦克风/通知等）默认拒绝——为后续键鼠视角控制预留通道；
- **F11 全屏**：经 `before-input-event` 实现，不占用系统全局快捷键；
- **外链兜底**：`setWindowOpenHandler` 拦截 `window.open`，http(s) 交系统浏览器，
  其余拒绝（游戏本身无外链，纯防御）。

`package.json` 构建配置要点：`appId: com.nagigames.ruinsbreakout`、
`productName: 废墟突围`、win target 同时含 `portable` 与 `nsis`（x64）、
NSIS 非一键安装（可选目录、建桌面/开始菜单快捷方式）。

---

## 五、轻量替代方案对比

| 维度 | Electron（本方案） | Neutralino | Tauri |
|---|---|---|---|
| 产物体积 | 150–250 MB | **5–15 MB** | 5–15 MB |
| 渲染内核 | 内置 Chromium | 系统 WebView2（Win10 1803+ 自带） | 系统 WebView2 |
| 工具链 | 本机 npm ✅ 已验证 | **免 npm**，下载 neu 二进制即用 | 需 Rust/cargo ❌ 本机没有 |
| 构建难度 | 一键脚本 | 解压即用，接近零配置 | 装 Rust 工具链 + 编译，最重 |
| API 能力 | 最完整（指针锁定/全屏/权限控制成熟） | 够用（窗口/文件/系统 API） | 最完整 |
| 内存占用 | 高（独立 Chromium） | 低 | 低 |
| 结论 | **主方案**：稳妥、能力全、本机零额外安装 | **备选**：小体积发行渠道 | **不推荐**：本机无 cargo |

### Neutralino 备选落地（简述）

1. 从 https://neutralino.js.org/docs/getting-started/installation 下载
   Neutralino Windows 二进制包（含 `neutralino-win_x64.exe` + `resources.neu` 结构），
   或使用 `npx @neutralinojs/neu create`（需 npm，但非必须——可直接下二进制）；
2. 将 `index.html` / `js/` / `css/` / `img/` 复制到其 `resources/` 目录；
3. 配置 `neutralino.config.json`：

```json
{
  "applicationId": "com.nagigames.ruinsbreakout",
  "version": "1.0.0",
  "defaultMode": "window",
  "port": 0,
  "documentRoot": "/resources/",
  "url": "/",
  "enableServer": false,
  "enableNativeAPI": true,
  "modes": {
    "window": {
      "title": "废墟突围",
      "width": 1280,
      "height": 720,
      "minWidth": 800,
      "minHeight": 450,
      "fullScreen": false,
      "alwaysOnTop": false,
      "enableInspector": false,
      "borderless": false,
      "resizable": true,
      "icon": "/resources/icons/appIcon.png"
    }
  },
  "cli": {
    "binaryName": "废墟突围",
    "distributionPath": "/dist",
    "resourcesPath": "/resources"
  }
}
```

4. `neu build --release` 产出约 5–15 MB 的单 exe（依赖系统 WebView2，
   Win10 1803+ / Win11 均内置）。
   **注意**：Neutralino 对 Pointer Lock 的支持取决于 WebView2 版本，
   键鼠适配落地前需实测验证。

### Tauri 为何不推荐

Tauri 产物小且能力强，但构建必须走 Rust 工具链（`cargo` + MSVC Build Tools，
首次安装 ~2GB 且需编译 5–15 分钟）。本机系统 PATH 无 cargo、无独立 Rust 环境，
为「套壳一个静态页」引入整套 Rust 工具链性价比过低；若未来需要原生能力
（存档系统/硬件信息）再评估不迟。

---

## 六、与键鼠适配的正交关系

- 本打包骨架**只负责窗口外壳与权限放行**，不触碰任何操控逻辑；
- 键鼠适配（Pointer Lock 锁定鼠标、WASD/鼠标视角/键位映射、触屏 UI 在桌面端的显隐）
  属于游戏层改造，落地后同样经由 `build.ps1` 的复制步骤自动进入 `app/`，
  打包链路无需任何改动；
- 反向亦成立：键鼠适配未完成时，本骨架产出的桌面版可直接以触屏 UI + 鼠标点击
  虚拟按钮的方式先行验证打包链路。

---

## 附：本方案产出文件清单

| 文件 | 作用 |
|---|---|
| `desktop-port/electron/package.json` | 依赖声明 + electron-builder 构建配置 |
| `desktop-port/electron/main.js` | Electron 主进程 |
| `desktop-port/electron/build.ps1` | 一键构建脚本 |
| `desktop-port/electron/.gitignore` | 忽略 node_modules / dist / app |
| `desktop-port/electron/build/README.md` | 图标占位说明 |
| `desktop-port/02-packaging.md` | 本文档 |

**未执行项（按任务约束）**：未运行 `npm install`（网络与耗时不可控），
首次构建由使用方双击 `build.ps1` 触发。
