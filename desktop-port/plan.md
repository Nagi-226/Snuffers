# 废墟突围 — Windows 桌面端（.exe）移植计划

## 背景事实（已核实）
- 游戏本体：`index.html`（3501 行）+ `js/three.min.js` (r128) + `js/cannon.min.js` (0.6.2) + `css/tailwind.css` + `img/title-bg.jpg`，全离线
- 操控：仅触屏（虚拟摇杆 + 触控按钮），无键鼠事件
- 工具链：Node v24.15.0 + npm（kimi-desktop 内置 runtime，npm.cmd 可用）；Godot 4.6.2 stable 在 `D:\Godot_v4.6.2-stable_win64.exe`
- Godot 无法直接包装 Three.js 应用；Godot 路径 = GDScript 全量重写

## 阶段分工（并行子代理）
1. **键鼠操控适配设计师** → 通读 index.html，盘点全部触屏绑定与动作函数，设计键鼠映射 + Pointer Lock 视角方案 + 桌面端 UI 隐藏策略，给出精确插入点。产出：`desktop-port/01-input-adaptation.md`
2. **桌面打包工程师** → 基于本机 npm 设计并创建 Electron 打包骨架（package.json / main.js / build.ps1），附轻量替代方案对比。产出：`desktop-port/02-packaging.md` + `desktop-port/electron/` 骨架
3. **Godot 重写可行性评估员** → 评估 Godot 4.6.2 重写各子系统的映射关系、工作量与风险，明确"现在用 / 未来重制再用"的结论。产出：`desktop-port/03-godot-assessment.md`

## 阶段门
- 三份报告齐全 → 主代理整合为 `desktop-port/README.md` 最终方案（推荐路径 + 实施步骤 + 工作量）
- 键鼠适配与打包骨架不修改游戏源文件；实际改造待用户确认方案后执行
