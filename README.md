# Ruins Breakout - Tactical Remake (离线包)

## 项目结构

```
Ruins-Breakout-Tactical-Remake/
├── index.html          # 主游戏文件 (单页应用)
├── css/
│   └── tailwind.css    # Tailwind CSS 样式库
├── js/
│   ├── three.min.js    # Three.js 3D 引擎 (r128)
│   └── cannon.min.js   # Cannon.js 物理引擎 (v0.6.2)
└── img/
    └── title-bg.jpg    # 标题界面背景图
```

## 运行方式

### 方法 1: 直接打开 (推荐)
双击 `index.html`，使用现代浏览器（Chrome / Edge / Safari）打开即可运行。

> ⚠️ 由于使用了 ES6 模块和本地文件协议，**建议通过本地服务器运行**以获得最佳体验：

### 方法 2: 本地服务器 (更稳定)

#### Python 3
```bash
cd Ruins-Breakout-Tactical-Remake
python -m http.server 8080
```
然后访问 `http://localhost:8080`

#### Node.js (若已安装)
```bash
cd Ruins-Breakout-Tactical-Remake
npx serve
```

#### VS Code
安装 "Live Server" 插件，右键 `index.html` → "Open with Live Server"

## 游戏操作

| 操作 | 方式 |
|------|------|
| 视角控制 | 滑动屏幕 |
| 移动 | 左下角虚拟摇杆 |
| 开火 | 左侧红色按钮 |
| 瞄准 | 右下角黄色按钮 |
| 切换武器 | 右下角紫色按钮 (步枪 ↔ 火箭筒) |
| 趴下 | 右侧灰色按钮 |
| 换弹 | 右下角蓝色按钮 |
| 夜视仪 | 顶部绿色按钮 |
| 呼叫直升机 | 右上角黄色按钮 |
| 地图 | 左上角按钮 |
| 使用药包 | 右上角红心按钮 (获得后显示) |

## 打包说明

此版本已将所有 CDN 依赖转为本地引用，可完全离线运行。
- Three.js 和 Cannon.js 为官方 CDN 下载的原始文件
- Tailwind CSS 为 CDN 生成的完整样式表
- 背景图片已下载到本地

## 浏览器兼容性

- Chrome 90+
- Edge 90+
- Safari 14+ (iOS 14+)
- Firefox 90+

需要支持 WebGL 和 Touch Events。
