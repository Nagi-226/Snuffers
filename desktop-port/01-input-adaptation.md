# 废墟突围 · 桌面端键鼠操控适配设计（01-input-adaptation）

> 角色：键鼠操控适配设计师　｜　分析对象：`index.html`（全文 3502 行已通读）
> 阶段产出：仅分析与设计，**不修改** `index.html`。所有行号以当前版本 `index.html` 为准。

---

## 结论先行

1. **视角与移动的数据流非常干净**：触屏输入最终只写入 4 个状态变量——`Game.rotX`（偏航）、`Game.rotY`（俯仰）、`Game.moveX`（横移）、`Game.moveY`（前后）；消费方只有 `updateMovement()`（第 3149–3192 行）一处。因此键鼠适配无需改动任何游戏逻辑，只需在输入层把这 4 个变量按相同公式写出来即可。
2. **开火/换弹/夜视/药包/直升机已有命名函数**（`startFiring`/`stopFiring`/`reload`/`toggleNightVision`/`useMedkit`/`callHelicopter`），键鼠可直接复用；**瞄准、切枪、趴下、地图 4 个动作是匿名函数**，需要先做"命名化重构"（提取为 `toggleAim`/`switchWeapon`/`toggleProne`/`openMap`/`closeMap`），这是本方案唯一需要改动现有行的部分。
3. **Pointer Lock + `mousemove.movementX/Y` 可以完全复刻触屏视角公式**（`delta * 0.002 * sens`，俯仰钳制 ±1.2），连开镜灵敏度衰减系数 0.3 都直接照搬。
4. **桌面端 UI 策略用"JS 检测 + body 类名"**：非触屏设备加 `body.desktop-mode`，CSS 一条规则隐藏全部 10 个触屏控件并显示键鼠提示条；不依赖 `@media (hover: pointer)`（Electron/Tauri 内嵌 WebView 对该媒体特性支持不一致）。
5. **插入点集中**：CSS 追加在第 145 行后（`</style>` 前）；DOM 追加在第 255 行后；输入层 JS 作为一个独立 IIFE 插入第 2596 行后（所有被复用函数均为 `function` 声明、已提升，位置安全）；仅 4 处现有代码需重构、2 处需追加单行。

---

## 1. 触屏事件绑定清单（全量盘点）

| # | 元素 id / 目标 | 事件 | 调用/逻辑 | 行号 |
|---|---|---|---|---|
| 1 | `document`（排除控件列表见 2359 行） | `touchstart` | 记录视角触点 `viewTouchId/viewStartX/viewStartY` | 2358–2364 |
| 2 | `document` | `touchmove` | 视角旋转：写 `Game.rotX/rotY`（公式见 §2.1） | 2365–2380 |
| 3 | `document` | `touchend` | 清空 `viewTouchId` | 2381–2384 |
| 4 | `joystickZone`（`#joystick-zone`） | `touchstart` | 记录 `joystickTouchId` → `handleJoystickMove()` | 2388–2394 |
| 5 | `joystickZone` | `touchmove` | → `handleJoystickMove()` | 2395–2402 |
| 6 | `joystickZone` | `touchend` | 摇杆复位：`Game.moveX = 0; Game.moveY = 0` | 2403–2412 |
| 7 | `fireBtn` | `touchstart` / `touchend` | `startFiring()`（2424）/ `stopFiring()`（2437） | 2443–2444 |
| 8 | `aimBtn` | `touchstart` | **匿名函数**：切换 `Game.isAiming` + 开镜 UI/武器位移 | 2448–2482 |
| 9 | `weaponBtn` | `touchstart` | **匿名函数**：切换 `Game.currentWeapon` rifle↔rpg + 瞄具 UI 切换 | 2485–2510 |
| 10 | `proneBtn` | `touchstart` | **匿名函数**：切换 `Game.isProne` + 相机高度/移速 | 2513–2524 |
| 11 | `callHeliBtn` | `touchstart` | `callHelicopter()`（定义 3366–3421） | 2527 |
| 12 | `reloadBtn` | `touchstart` | `reload()`（定义 2530–2541） | 2529 |
| 13 | `mapBtn` | `touchstart` | **匿名**：`Game.mapOpen = true; drawFullMap()` | 2595 |
| 14 | `closeMap` | `touchstart` | **匿名**：`Game.mapOpen = false` | 2596 |
| 15 | `nvBtn` | `touchstart` | `toggleNightVision()`（定义 375–400） | 401 |
| 16 | `medkitBtn` | `touchstart` | `useMedkit()`（定义 691–708） | 709 |
| 17 | `document` | `touchmove` | canvas 上 `preventDefault()`（防页面滚动） | 3493 |

**非触屏（鼠标已天然可用）的绑定，供参考**：

| 元素 | 事件 | 逻辑 | 行号 |
|---|---|---|---|
| `settingsBtn` / `closeSettings` / `settingsOverlay` | `onclick` | 设置面板开关 | 3111–3113 |
| `senseSlider` | `oninput` | 写 `Config.viewSensitivity` | 3114 |
| `startBtn` | `onclick` | 隐藏菜单 → `initGame()` → 任务简报 | 3328–3334 |
| `missionInfoBtn` | `click` | 显示全部 HUD（移除 `hidden`）、`Game.active = true; animate()` | 3336–3364 |
| `gameOver` 内按钮 | `onclick="location.reload()"` | 重开 | 233 |

**关键空白**：全文件**没有任何 `keydown`/`keyup`/`mousedown`/`mousemove`/Pointer Lock 绑定**——键鼠层是从零新增，不触碰现有事件路径。

---

## 2. 视角与移动控制机制分析

### 2.1 视角：touchmove → 相机旋转

**写入侧**（第 2365–2380 行，`document.touchmove`）：

```js
const deltaX = touch.clientX - viewStartX, deltaY = touch.clientY - viewStartY;
const sens = Game.isAiming ? Config.viewSensitivity * 0.3 : Config.viewSensitivity;
Game.rotX -= deltaX * 0.002 * sens;                 // 偏航（yaw）
Game.rotY -= deltaY * 0.002 * sens;                 // 俯仰（pitch）
Game.rotY = Math.max(-1.2, Math.min(1.2, Game.rotY)); // 俯仰钳制 ±1.2 rad (≈±68.8°)
viewStartX = touch.clientX; viewStartY = touch.clientY;
```

- `Config.viewSensitivity` 默认 2.0（第 277 行），设置面板滑块可调 0.3–5.0（第 224、3114 行）。开镜时灵敏度 ×0.3。
- **另一处写入**：开火后坐力 `Game.rotY += 0.003`（第 2691 行，`shoot()` 内）——键鼠方案无需干预，自然生效。
- 初始值：`Game.rotX = Math.PI * 0.75; Game.rotY = 0;`（第 2353–2354 行）。

**消费侧**（第 3151–3153 行，`updateMovement()` 内，每帧执行）：

```js
camera.rotation.order = 'YXZ';
camera.rotation.y = Game.rotX;   // YXZ 顺序下 y 即世界偏航
camera.rotation.x = Game.rotY;
```

同一份消费逻辑也出现在撤离成功动画 `missionComplete()`（第 3222–3224 行）。结论：**键鼠只需把 `movementX/Y` 按同一公式累加进 `Game.rotX/rotY`，相机即正确旋转，零额外适配。**

### 2.2 移动：虚拟摇杆 → 移动向量

**写入侧**（`handleJoystickMove()`，第 2413–2421 行）：

```js
let dx = clientX - centerX, dy = clientY - centerY;
const distance = Math.sqrt(dx*dx + dy*dy), maxDistance = 35;
if (distance > maxDistance) { /* 等比截断到 35px 半径 */ }
Game.moveX = dx / maxDistance;    // 右为正，∈ [-1, 1]
Game.moveY = -(dy / maxDistance); // 上（前）为正，∈ [-1, 1]
```

松手复位：`Game.moveX = 0; Game.moveY = 0;`（第 2409 行）。

**消费侧**（`updateMovement()`，第 3149–3192 行，逐帧）：

```js
const inputX = Game.moveX * Game.moveSpeedMultiplier;   // 3154
const inputY = Game.moveY * Game.moveSpeedMultiplier;
if (Math.abs(inputX) < 0.1 && Math.abs(inputY) < 0.1) { Game.playerSpeed = 0; }  // 死区 0.1（乘速后）
else {
    const speed = Game.isAiming ? 0.05 : (Game.isProne ? 0.08 : 0.15);          // 每帧位移（60fps 基准）
    const forward = new THREE.Vector3(0, 0, -1).applyAxisAngle(Y轴, Game.rotX);
    const right   = new THREE.Vector3(1, 0, 0).applyAxisAngle(Y轴, Game.rotX);
    newPos.x += (right.x * inputX + forward.x * inputY) * speed;
    newPos.z += (right.z * inputX + forward.z * inputY) * speed;
    // 地图边界钳制 x∈[-98,98] z∈[-58,58]（3167–3168）；checkObstacleCollision 碰撞+轴向滑动（3170–3183）
}
```

- `Game.moveSpeedMultiplier` 由腿部伤情决定：健康 1.5 / 受伤 0.75 / 重伤 0.375 / 趴下 0.15（`updateMoveSpeed()` 第 2969–2981 行）。
- 注意：`Game.playerSpeed`/`playerStillTime`（第 3184–3191 行）喂给狙击手 AI 的"打静止目标"判定（第 908–914 行），键鼠桥接只要照实写 `moveX/moveY`，该机制自动保持平衡。

**结论：键盘桥接就是把 WASD 状态合成为 `Game.moveX/moveY ∈ [-1,1]`**（数字摇杆只有 0/±1 档，等价于摇杆推满），`updateMovement` 无需任何改动。

---

## 3. 键鼠映射表（逐个注明复用的现有函数）

| 输入 | 动作 | 实现方式 / 复用的现有函数 |
|---|---|---|
| **鼠标移动**（Pointer Lock 锁定后） | 视角旋转 | 新增 `onMouseMove`，公式复刻第 2371–2376 行：写 `Game.rotX/rotY`，含开镜 ×0.3 灵敏度与 ±1.2 钳制 |
| **W / ↑** | 前进 | 键盘状态机 → `Game.moveY = +1`（桥接，见 §5.4） |
| **S / ↓** | 后退 | → `Game.moveY = -1` |
| **A / ←** | 左移 | → `Game.moveX = -1` |
| **D / →** | 右移 | → `Game.moveX = +1`（对角线合成后归一化到模长 ≤1，见 §5.4） |
| **鼠标左键**（按下/松开） | 开火 / 停火（步枪连发、火箭筒单发由 `startFiring` 内部按 `currentWeapon` 分流，第 2429–2435 行） | `mousedown(btn0)` → `startFiring()`（2424）；`mouseup(btn0)` → `stopFiring()`（2437） |
| **鼠标右键**（点击） | 瞄准开/关（切换式，与触屏语义一致） | `mousedown(btn2)` → `toggleAim()`（由 2448–2482 匿名体重构而来）；`contextmenu` 需 `preventDefault()` |
| **R** | 换弹 | `reload()`（2530；内部已含 rpg/满弹/无备弹守卫） |
| **C** | 趴下/起身 | `toggleProne()`（由 2513–2524 匿名体重构而来） |
| **1** | 切步枪 | `if (Game.currentWeapon !== 'rifle') switchWeapon()`（重构自 2485–2510） |
| **2** | 切火箭筒 | `if (Game.currentWeapon !== 'rpg') switchWeapon()` |
| **V** | 夜视开关 | `toggleNightVision()`（375） |
| **H** | 呼叫直升机 | `callHelicopter()`（3366；内部已含距离守卫） |
| **M / Tab** | 地图开/关 | `openMap()` / `closeMap()`（重构自 2595–2596；Tab 需 `preventDefault()` 防焦点跳转） |
| **F** | 使用药包 | `useMedkit()`（691；内部已含数量守卫） |
| **Esc** | 释放指针 → 暂停 | 浏览器原生行为退出 Pointer Lock；新增 `pointerlockchange` 监听 → `stopFiring()` + 显示暂停遮罩；点击遮罩 → 重新 `requestPointerLock()` 恢复 |

**按键重复（key repeat）处理**：所有切换类动作（瞄准/趴下/切枪/夜视/地图/药包/直升机）只在 `keydown` 且 `!e.repeat` 时触发一次；移动键用 `keys{}` 状态表，`keyup` 清除。

**开火是按住语义**：左键 `mousedown`→`startFiring`、`mouseup`→`stopFiring`，天然对应；同时补 `window blur` 与暂停时强制 `stopFiring()`，防"卡枪"。

---

## 4. 桌面端 UI 策略（隐藏触屏控件 + 键鼠提示）

### 4.1 设备检测：JS 为主，不用 CSS 媒体特性

`@media (hover: hover) and (pointer: fine)` 在 Electron / Tauri / WebView2 等内嵌内核中行为不一致（部分环境报 `pointer: none`），故采用 **JS 检测写 body 类名 + CSS 类选择器**，双保险：

```js
// 插入在输入层 IIFE 顶部（§5.3）
const isTouch = ('ontouchstart' in window) || navigator.maxTouchPoints > 0;
const hasFinePointer = window.matchMedia('(hover: hover) and (pointer: fine)').matches;
if (!isTouch || hasFinePointer) document.body.classList.add('desktop-mode');
```

判定逻辑：`hasFinePointer` 为真一律走桌面模式（覆盖 Surface 类"触屏+鼠标"设备）；否则看 `ontouchstart`/`maxTouchPoints`。

### 4.2 CSS 规则（插入第 145 行 `#fpsDisplay` 规则之后、`</style>`（第 146 行）之前）

```css
/* —— 桌面端（键鼠）UI 适配 —— */
body.desktop-mode #fireBtn, body.desktop-mode #reloadBtn,
body.desktop-mode #aimBtn, body.desktop-mode #proneBtn,
body.desktop-mode #weaponBtn, body.desktop-mode #callHeliBtn,
body.desktop-mode #medkitBtn, body.desktop-mode #mapBtn,
body.desktop-mode #nvBtn, body.desktop-mode #joystick-zone { display: none !important; }
body.desktop-mode { cursor: default; }
body.desktop-mode.pointer-locked { cursor: none; }   /* 锁定时隐藏系统光标，准星已在画面中央 */

/* 键鼠提示条（游戏内常驻右下角） */
#desktopHint { position: fixed; right: 10px; bottom: 10px; z-index: 95; display: none;
    background: rgba(0,0,0,0.75); border: 1px solid rgba(0,255,0,0.3); border-radius: 6px;
    color: #00ff00; font-size: 10px; font-family: monospace; padding: 6px 10px; line-height: 1.6;
    pointer-events: none; white-space: nowrap; }
body.desktop-mode #desktopHint { display: block; }

/* 暂停遮罩（Esc 释放指针后显示，点击恢复） */
#pauseOverlay { position: fixed; inset: 0; z-index: 400; display: none;
    background: rgba(0,0,0,0.7); flex-direction: column; align-items: center; justify-content: center;
    color: #00ff00; font-family: 'Microsoft YaHei', sans-serif; cursor: pointer; }
#pauseOverlay.active { display: flex; }

/* 开始菜单：桌面端显示键鼠操作指南，隐藏触屏指南 */
body.desktop-mode #touchGuide { display: none; }
body:not(.desktop-mode) #desktopGuide { display: none; }
```

> 说明：HUD 元素在第 3339–3350 行由 `missionInfoBtn` 统一移除 `hidden` 类，`display: none !important` 优先级高于 `.hidden` 的移除动作，桌面端控件不会被重新显示。保留 `#settingsBtn`（齿轮）与 `#ammoDisplay`/`#healthDisplay` 等纯信息 HUD——它们桌面端仍有用且本就可用鼠标。

### 4.3 DOM 追加（第 255 行 `#fpsDisplay` div 之后）

```html
<div id="desktopHint">WASD 移动 | 鼠标 视角 | 左键 开火 | 右键 瞄准 | R 换弹 | C 趴下 | 1/2 切枪 | V 夜视 | H 直升机 | M 地图 | F 药包 | Esc 暂停</div>
<div id="pauseOverlay"><div style="font-size:28px;font-weight:bold;">已暂停</div><div style="margin-top:12px;font-size:14px;">点击屏幕继续任务</div></div>
```

开始菜单操作指南（第 262–271 行 `<ul>`）加一对双份列表：现有 `<ul>` 包一层 `<div id="touchGuide">`，旁边新增 `<div id="desktopGuide">` 同结构键鼠版文案；由 §4.2 的 CSS 按设备自动二选一（此属重构项 M6，见 §5.6）。

---

## 5. 精确插入计划

> 总览：**新增 3 块**（CSS / DOM / 输入层 IIFE），**改动现有 6 处**（M1–M6，其中 M1–M4 为匿名函数命名化重构，逻辑零变化）。

### 5.1 新增块 A：CSS —— 第 145 行之后（见 §4.2，整段照抄）

### 5.2 新增块 B：DOM —— 第 255 行之后（见 §4.3）

### 5.3 新增块 C：输入层 IIFE —— 插入第 2596 行（`closeMap` 绑定）之后、第 2598 行（`function drawFullMap`）之前

位置依据：此处所有触屏控件绑定已就绪；被复用的 `startFiring/stopFiring/reload/toggleNightVision/useMedkit/callHelicopter` 均为 `function` 声明，整个 `<script>` 作用域内已提升，调用安全；`toggleAim/switchWeapon/toggleProne/openMap/closeMap` 由重构 M1–M4 在同作用域提供。

```js
/* ================= 桌面端键鼠输入层（desktop-port 新增） ================= */
(function initDesktopInput() {
    const isTouch = ('ontouchstart' in window) || navigator.maxTouchPoints > 0;
    const hasFinePointer = window.matchMedia('(hover: hover) and (pointer: fine)').matches;
    if (!isTouch || hasFinePointer) document.body.classList.add('desktop-mode');
    if (!document.body.classList.contains('desktop-mode')) return;   // 纯触屏设备：不启用键鼠层

    const keys = Object.create(null);
    let pointerLocked = false;

    // —— 5.3.1 Pointer Lock：锁定/释放状态机 + 暂停遮罩 ——
    function requestLock() {
        if (document.pointerLockElement !== canvas) canvas.requestPointerLock();
    }
    document.addEventListener('pointerlockchange', () => {
        pointerLocked = (document.pointerLockElement === canvas);
        document.body.classList.toggle('pointer-locked', pointerLocked);
        if (!pointerLocked && Game.active && !Game.mapOpen) {
            stopFiring();                       // 防卡枪
            Game.moveX = 0; Game.moveY = 0;     // 防"幽灵移动"
            document.getElementById('pauseOverlay').classList.add('active');
        }
    });
    document.getElementById('pauseOverlay').addEventListener('click', () => {
        document.getElementById('pauseOverlay').classList.remove('active');
        requestLock();
    });
    canvas.addEventListener('click', () => { if (Game.active && !pointerLocked && !Game.mapOpen) requestLock(); });

    // —— 5.3.2 鼠标视角：完全复刻触屏公式（原 2371–2376 行） ——
    document.addEventListener('mousemove', (e) => {
        if (!pointerLocked || !Game.active || Game.mapOpen) return;
        const sens = Game.isAiming ? Config.viewSensitivity * 0.3 : Config.viewSensitivity;
        Game.rotX -= e.movementX * 0.002 * sens;
        Game.rotY -= e.movementY * 0.002 * sens;
        Game.rotY = Math.max(-1.2, Math.min(1.2, Game.rotY));
    });

    // —— 5.3.3 鼠标按键：左键开火 / 右键瞄准 ——
    canvas.addEventListener('mousedown', (e) => {
        if (!Game.active || Game.mapOpen || !pointerLocked) return;
        if (e.button === 0) startFiring();
        else if (e.button === 2) toggleAim();          // 切换式，与触屏语义一致
    });
    document.addEventListener('mouseup', (e) => { if (e.button === 0) stopFiring(); });
    canvas.addEventListener('contextmenu', (e) => e.preventDefault());
    window.addEventListener('blur', () => { stopFiring(); for (const k in keys) keys[k] = false; syncMoveFromKeys(); });

    // —— 5.3.4 键盘状态机 + 摇杆向量桥接 ——
    function syncMoveFromKeys() {
        let mx = 0, my = 0;
        if (keys['KeyW'] || keys['ArrowUp'])    my += 1;
        if (keys['KeyS'] || keys['ArrowDown'])  my -= 1;
        if (keys['KeyA'] || keys['ArrowLeft'])  mx -= 1;
        if (keys['KeyD'] || keys['ArrowRight']) mx += 1;
        const len = Math.hypot(mx, my);                 // 对角线归一化，与摇杆模长上限 1 对齐
        if (len > 1) { mx /= len; my /= len; }
        Game.moveX = mx; Game.moveY = my;               // 直接喂给 updateMovement()（原 3154 行）
    }

    document.addEventListener('keydown', (e) => {
        if (!Game.active) return;
        if (['ArrowUp','ArrowDown','ArrowLeft','ArrowRight','Tab','Space'].includes(e.code)) e.preventDefault();
        keys[e.code] = true;
        syncMoveFromKeys();
        if (e.repeat) return;                           // 切换类动作只触发一次
        switch (e.code) {
            case 'KeyR': reload(); break;
            case 'KeyC': toggleProne(); break;
            case 'Digit1': if (Game.currentWeapon !== 'rifle') switchWeapon(); break;
            case 'Digit2': if (Game.currentWeapon !== 'rpg')   switchWeapon(); break;
            case 'KeyV': toggleNightVision(); break;
            case 'KeyH': callHelicopter(); break;
            case 'KeyF': useMedkit(); break;
            case 'KeyM': case 'Tab':
                if (Game.mapOpen) closeMap(); else openMap();
                break;
        }
    });
    document.addEventListener('keyup', (e) => { keys[e.code] = false; syncMoveFromKeys(); });
})();
/* ============== 桌面端键鼠输入层结束 ============== */
```

**为什么桥接直接写 `Game.moveX/moveY` 就够**：`updateMovement()`（第 3149 行起）每帧读取这两个变量；桌面模式下触屏摇杆已隐藏、其 `touchend` 复位逻辑（第 2403–2412 行）永远不会触发，不存在写入竞争。键盘松手即 `syncMoveFromKeys()` 写 0，等价于摇杆复位。

### 5.4（并入 5.3 代码块，桥接即 `syncMoveFromKeys`）

### 5.5 需改动的现有行（重构项，逐一列出）

| 编号 | 行号区间 | 改动内容 | 说明 |
|---|---|---|---|
| **M1** | 2448–2482 | 把 `aimBtn` 匿名 handler 函数体提取为 `function toggleAim() { … }`；监听器改为 `aimBtn.addEventListener('touchstart', (e) => { e.preventDefault(); toggleAim(); });` | 函数体逐字搬迁，逻辑零变化 |
| **M2** | 2485–2510 | 同上，提取为 `function switchWeapon() { … }`（保留 `if (Game.mapOpen) return;` 守卫） | 同上 |
| **M3** | 2513–2524 | 同上，提取为 `function toggleProne() { … }` | 同上 |
| **M4** | 2595–2596 | 提取为 `function openMap() { Game.mapOpen = true; mapModal.style.display = 'flex'; drawFullMap(); }` 与 `function closeMap() { Game.mapOpen = false; mapModal.style.display = 'none'; }`；两个 `touchstart` 监听器改为调用它们；**同时给 `closeMap` 补一个 `click` 监听**（原仅 `touchstart`，桌面鼠标点不动） | 桌面可用性修复 |
| **M5** | 3336–3364（`missionInfoBtn` click handler 内，`Game.active = true;`（3361 行）之后追加 2 行） | `if (document.body.classList.contains('desktop-mode')) { canvas.requestPointerLock(); }` | 点击"收到"是合法用户手势，可直接请求 Pointer Lock；`animate()`（3363 行）保持不变 |
| **M6** | 262–271（开始菜单操作指南 `<ul>`） | 外层包 `<div id="touchGuide">`，并新增同结构 `<div id="desktopGuide">` 键鼠版文案 | 纯展示层，由 §4.2 CSS 二选一显示 |

**不需要改动的关键点**（确认过）：
- 第 2359 行视角触点排除列表——桌面端该 `touchstart` 路径不触发，无需增删。
- `updateMovement()`（3149–3192）、`shoot()`（2685）、`fireRPG()`（2809）、`animate()`（3440–3491）——全部通过 `Game.*` 状态间接驱动，零改动。
- 游戏没有独立暂停循环：暂停遮罩期间 `animate()` 仍运行（敌人继续行动）。这是**有意选择**——与触屏端打开地图时的行为一致（`Game.mapOpen` 只冻结输入不冻结世界），不引入新的暂停语义、不改主循环。若后续需要"真暂停"，再在第 3453 行 `world.step(dt)` 前加 `if (!Game.paused)` 守卫即可，本阶段不做。

### 5.6 验证清单（实施后用）

1. 桌面浏览器打开 → 10 个触屏控件不可见、右下键鼠提示条可见、开始菜单显示键鼠指南。
2. 点击"收到"→ 指针锁定、光标隐藏；动鼠标视角转、开镜后视角变慢（×0.3）、俯仰到顶/到底被钳住。
3. WASD/方向键移动、斜向不快于直线；腿部受伤后移速下降（走 `moveSpeedMultiplier`，自动生效）。
4. 左键按住连发、松开停火；弹匣打空自动换弹（`shoot()` 第 2687 行原有逻辑）。
5. 右键开镜/关镜；R/C/1/2/V/H/M/Tab/F 各动作与触屏按钮逐一等价；Esc → 暂停遮罩 → 点击恢复锁定。
6. 触屏设备（或 DevTools 触屏模拟）→ `desktop-mode` 不生效，原触屏体验完全不变。

---

## 附：关键行号速查

| 内容 | 行号 |
|---|---|
| `Game` 状态对象（`moveX/moveY/rotX/rotY/isAiming/isProne/mapOpen…`） | 278 |
| 相机/视角初值 `Game.rotX = π·0.75` | 2352–2355 |
| 视角 touchmove 公式（复刻对象） | 2365–2380 |
| 摇杆 → `moveX/moveY`（`handleJoystickMove`） | 2413–2421 |
| `startFiring` / `stopFiring` | 2424 / 2437 |
| 瞄准匿名体（→ `toggleAim`） | 2448–2482 |
| 切枪匿名体（→ `switchWeapon`） | 2485–2510 |
| 趴下匿名体（→ `toggleProne`） | 2513–2524 |
| 地图开/关匿名体（→ `openMap`/`closeMap`） | 2595–2596 |
| `reload` / `toggleNightVision` / `useMedkit` / `callHelicopter` | 2530 / 375 / 691 / 3366 |
| `updateMovement`（输入唯一消费方） | 3149–3192 |
| `missionInfoBtn` 开始游戏（M5 插入点） | 3336–3364 |
| 主循环 `animate` | 3440–3491 |
