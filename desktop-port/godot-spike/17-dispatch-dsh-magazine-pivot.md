# 《熄烛者》Snuffers — W9 深度蜂 第三单：弹匣枢轴原点设置（换弹动画前置）

> 本文档 = 蜂后派单提示词全文（2026-10-18，第三单），可直接整篇复制粘贴给 DeepSeek Harness。
> 前置：派单 14/15 均已通过 L3 审查 + Godot 导入验证；本单处理你报告 6-4 的遗留项。

## 你的角色与边界（继承前两单）

你是 W9「深度蜂」，外部 IDE Agent（DeepSeek Harness + V4.1-Flash-1017），负责**武器资产后处理域**。仓库：`E:\Github Project\Nagi_Games\Snuffers`，分支 **dev1**（禁止碰 master，禁止 rebase/force-push）。

**可写域**：`desktop-port/godot-spike/modeling/` + `desktop-port/godot-spike/03-handoff-<日期>.md`。
**绝对禁改**：`godot/` 目录一切、autoload 三件套、`tools/`、`tests/`、`.gitignore`、他人文档。
Blender：`D:\steam\steamapps\common\Blender\blender.exe`，仅 headless（`-b --factory-startup --python-exit-code 1 --python`）。

## 入场纪律

1. 读 `AGENTS.md`；读 `desktop-port/godot-spike/03-handoff-2026-10-18-w9.md`（你上一班交接）
2. `git pull origin dev1`；`git status` + `git log --oneline -3` 确认无半截改动
3. 他人未提交改动一律不碰；显式路径 `git add`，禁用 `git add -A`

## 任务：为两个 viewmodel 的弹匣设置动画用枢轴原点

输入（均在 `desktop-port/godot-spike/modeling/em-weapons/`）：
- `em68a_viewmodel.glb`（4 对象：body / magazine / optic / gl_module）
- `em57p_viewmodel.glb`（4 对象：body / magazine / optic / laser_module）

### 要做什么

把 **magazine 子对象的局部原点**从「模型几何中心」迁移到**弹匣顶端中心**（弹匣插入弹井的入口面中心）——程序化换弹动画将以该点为枢轴做拔插/旋转。em68a 参考你报告 §6-4 给的 bbox 坐标（Y−0.27 / Z−0.21 附近是 em57p 的；em68a 的以实测为准，**两枪的弹匣顶面位置各自实测，不许互抄**）。

- 其余三个对象（body / optic / gl_module / laser_module）原点**保持不动**
- 做法：`Object > Set Origin` 等价 API（`bpy.ops.object.origin_set` 或直接改 mesh 顶点局部坐标 + 对象 matrix_world 补偿），**弹匣在世界空间的位置必须零变化**——只动原点，不动世界几何

### 最高优先级禁令（继承，一字不改）

禁止任何形式的减面/重拓扑/顶点合并/重采样、禁止重压缩贴图、禁止任何会改动视觉结果的"优化"。本单除「弹匣原点迁移」外不做任何其他变更。世界空间几何逐点不变是硬验收。

### 验收标准（物化）

1. 两个 viewmodel 重出（覆盖同名文件），magazine 原点实测坐标落在弹匣顶面中心（报告含三轴实测值与取点依据）
2. **世界空间几何零变化**：迁移前后弹匣顶点世界坐标集合哈希一致（你自己用 verify 工具加一条「世界空间位置守恒」断言来证，不许只报局部坐标）
3. 顶点数/三角面数/UV/贴图 sha256 与迁移前一致（em57p 沿用蜂后裁决口径：文件级 +39 平坦面复制为已知基线，与自身迁移前比即可）
4. 重跑回归：脚本必须幂等，两枪同批处理一把命令跑完
5. 报告 `weapon_postprocess_report_pivot.md`（或并入既有报告的修订章节）：前后原点坐标 / 世界空间守恒证据 / 未解决问题
6. Godot 侧验证归蜂后

## 工程纪律（继承）

- 小步提交，commit message 末尾 `自检: ①②③④ 通过`；只提 dev1
- 不确定的 Blender API 先查文档或 `--python-expr` 小步验证
- 30 分钟无进展暂停报告；出错先读完整堆栈，一次只改一处
- 收工写 `03-handoff-<日期>-w9.md`；GLB 产物是否入库由蜂后统一处理，你照旧只交脚本/报告/JSON
