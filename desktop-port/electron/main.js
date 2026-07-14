/**
 * 废墟突围 - Electron 主进程
 *
 * 设计要点：
 * 1. 加载 desktop-port/electron/app/index.html（由 build.ps1 从项目根目录复制，
 *    游戏源文件零修改）。
 * 2. 安全加固：nodeIntegration=false、contextIsolation=true、sandbox=true。
 *    游戏为纯静态离线页面，无需 Node 能力，可安全全开沙箱。
 * 3. 放行 pointerLock（鼠标锁定）权限请求，为后续键鼠适配铺路。
 * 4. F11 切换全屏；隐藏菜单栏。
 */
const { app, BrowserWindow, Menu, session } = require('electron');
const path = require('path');

const GAME_ENTRY = path.join(__dirname, 'app', 'index.html');

function createWindow() {
  const win = new BrowserWindow({
    width: 1280,
    height: 720,
    minWidth: 800,
    minHeight: 450,
    title: '废墟突围',
    autoHideMenuBar: true,
    backgroundColor: '#000000',
    webPreferences: {
      nodeIntegration: false,
      contextIsolation: true,
      sandbox: true,
      // 静态离线游戏，禁用远程内容与导航跳转
      webSecurity: true,
      allowRunningInsecureContent: false,
    },
  });

  // 彻底移除应用菜单
  Menu.setApplicationMenu(null);

  win.loadFile(GAME_ENTRY);

  // 放行 pointerLock 权限请求（Pointer Lock API，鼠标视角控制所依赖）
  // 注意：需在游戏请求锁定前注册，放在 loadFile 之后立即生效于后续请求
  win.webContents.session.setPermissionRequestHandler(
    (webContents, permission, callback) => {
      if (permission === 'pointerLock') {
        return callback(true);
      }
      // 其他权限默认拒绝（游戏不依赖摄像头/麦克风/通知等）
      return callback(false);
    }
  );

  // F11 全屏切换（before-input-event 不需要全局快捷键注册）
  win.webContents.on('before-input-event', (event, input) => {
    if (input.type === 'keyDown' && input.key === 'F11') {
      win.setFullScreen(!win.isFullScreen());
      event.preventDefault();
    }
  });

  // 拦截外链跳转：一切 http(s) 链接交给系统浏览器（游戏本身无外链，兜底用）
  win.webContents.setWindowOpenHandler(({ url }) => {
    if (url.startsWith('http')) {
      require('electron').shell.openExternal(url);
    }
    return { action: 'deny' };
  });
}

app.whenReady().then(() => {
  // 在 defaultSession 层面也注册一次 pointerLock 放行，
  // 覆盖部分 Electron 版本下权限请求走默认会话的情况
  session.defaultSession.setPermissionRequestHandler(
    (webContents, permission, callback) => {
      callback(permission === 'pointerLock');
    }
  );

  createWindow();

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});
