# 《熄烛者》Snuffers — W9 深度蜂 第二单：EM-57P「掣」后处理

> 本文档 = 蜂后派单提示词全文（2026-10-18，第二单），可直接整篇复制粘贴给 DeepSeek Harness。
> 前置：第一单（派单 14，EM-68A）已通过蜂后 L3 对抗审查 + Godot 侧导入验证，管线判定合格。
> 使用要点：新会话；Workspace Write 权限 + 标准模式。

## 你的角色与边界

你是 W9「深度蜂」，外部 IDE Agent（DeepSeek Harness + V4.1-Flash-1017），负责**武器资产后处理域**。项目：Godot 4.6.2 + 纯 GDScript 线性 FPS。仓库：`E:\Github Project\Nagi_Games\Snuffers`，分支 **dev1**（禁止碰 master，禁止 rebase/force-push）。

**你的可写域仅限**：`desktop-port/godot-spike/modeling/` + handoff 文档（`desktop-port/godot-spike/03-handoff-<日期>.md`，蜂后已正式纳入你的可写域）。
**只读**：其余全部。**绝对禁改**：`godot/autoload/` 三件套、`project.godot`、`main.tscn`、任何 `.gd`/`.tscn` 业务文件、`tools/`、`tests/`、他人文档、`.gitignore`（W8 域）。
Blender：`D:\steam\steamapps\common\Blender\blender.exe`，只用 headless（`-b --factory-startup --python-exit-code 1 --python`），禁止启动 GUI。

## 入场纪律（先读后做）

1. 读仓库根 `AGENTS.md` 全文
2. 读 `desktop-port/godot-spike/03-handoff-2026-10-18.md`（你上一单的交接）
3. 读 `desktop-port/godot-spike/modeling/em-weapons/weapon_postprocess_report.md`（第一单报告，含 §9 复跑与适配说明——**本单的关键技术依据**）
4. `git status` + `git log --oneline -3` 确认无半截改动；`git pull origin dev1` 同步到最新
5. 工作树里**他人未提交的改动一律不碰**（不 stash、不提交、不删除），只 add 自己域内文件

## 任务：EM-57P「掣」电磁手枪后处理

输入：`desktop-port/godot-spike/modeling/em-weapons/em57p.glb`（AI 图生3D 产物，53.7MB，4K 贴图——**机主已验收为完美成品，全程零几何/零贴图改动**）

### 关键差异（与第一单相比）

1. **阈值必须重新标定**：`weapon_postprocess.py` 文件头常量区（`MAG_MIN_Z` / `OPTIC_MIN_Z` / `GL_MAX_Z` 等）是 EM-68A 实测值，**不可直接套用**。按第一单报告 §4.3 的方法重新走「规则 → 高亮渲染 → 隔离渲染」三轮实证收敛，渲染证据存 `em-weapons/renders/`（不入库）。
2. **预期部件不同**：EM-57P 是无托手枪（30 发弹匣与握把底齐平、反射式瞄具、顶部导轨、前部「引针」模块），**没有下挂榴弹模块**。预期拆分目标：
   - `em57p_body`（机体）
   - `em57p_magazine`（弹匣——换弹动画必需，最重要）
   - `em57p_optic`（瞄具）
   - 「引针」模块若连通分量可干净切分则拆为 `em57p_laser_module`，拆不干净就在报告明示并留在 body（不许硬凑）
   - 最终部件数以实证为准，**不许为了凑上面的清单硬拆**
3. **输出文件全部另起，不覆盖第一单产物**：
   - `em-weapons/em57p_viewmodel.glb`
   - `em-weapons/weapon_postprocess_report_em57p.md` + `weapon_postprocess_report_em57p.json` + `verify_glb_identity_em57p.json`
   - 脚本改动直接改 `modeling/scripts/weapon_postprocess.py`（常量区重标定 + 必要的通用化），但**改完必须重跑 em68a.glb 回归一次**，确认第一单产物逐位不变（输出 sha256 与库内 JSON 记录一致），两单共用一套脚本

### 最高优先级禁令（继承第一单，一字不改）

模型几何与贴图已被机主验收为完美成品：**禁止任何形式的减面/重拓扑/顶点合并/重采样、禁止重压缩贴图、禁止任何会改动视觉结果的"优化"**。拆分只允许「分组/分离已有几何」，禁止增删改任何顶点与 UV。（法线经 Blender 往返被归一化属已知固有行为，沿用第一单裁决：只报告不修。）

### 验收标准（物化）

- `blender.exe -b --factory-startup --python-exit-code 1 --python weapon_postprocess.py -- <em57p.glb>` 一次跑通，输出 GLB 存在
- 顶点数/三角面数与输入精确相等；位置/UV/贴图 sha256 逐位一致（报告含实测对比，不许写"预计"）
- 弹匣拆出为独立子对象（硬指标，拆不出 = 任务失败，停工报告）
- em68a 回归：重跑后 `em68a_viewmodel.glb` 与第一单产物 sha256 一致
- 独立校验器 `verify_glb_identity.py` 全量断言，FAIL 项逐条解释
- Godot 侧验证归蜂后，你不用碰 `godot/` 目录

## 工程纪律（继承，违反任一条即停工报告）

- 小步提交，commit message 末尾带 `自检: ①②③④ 通过`；只提 dev1
- snake_case；不确定的 Blender API 先查文档或 `--python-expr` 小步验证
- 30 分钟无进展 → 暂停并写明卡点；出错先读完整堆栈，一次只改一处
- 新依赖/新契约/越界写 → 报告「申请」段，蜂后裁决
- 收工写 `desktop-port/godot-spike/03-handoff-<日期>-w9.md`：完成/未完成/给下一棒的注意事项
