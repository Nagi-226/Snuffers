# ATTRIBUTION.md — enemy models

## Spore Husk（2026-10-31 绑骨动画版）

- 正式资产：`spore_husk_animated.glb`。
- 原始模型：项目自有概念设定经混元 3D 生成，原始文件保留在 `desktop-port/godot-spike/modeling/enemies/spore_husk/`。
- 权属：项目自有 AI 生成资产，无第三方署名要求。
- 本地处理：Blender 自定义核心/外膜/6 伪足骨架（共 8 骨），约 1.5 万三角面；idle/crawl/alert/leap/land/death 六组动作。
- 行为：蜗牛式贴地蠕动 + CharacterBody 抛物线跳扑；动画不代替物理位移。

## Hulking Host（2026-10-31 绑骨动画版）

- 正式资产：`hulking_host_animated.glb`。
- 原始模型：项目自有概念设定经混元 3D 生成，原始文件保留在 `desktop-port/godot-spike/modeling/enemies/hulking_host/`。
- 权属：项目自有 AI 生成资产，无第三方署名要求。
- 本地处理：Blender 16 骨人形骨架，约 1.5 万三角面，独立 upper_arm_r/forearm_r/hand_r 右臂链；idle/walk/attack/death 四组动作。
- 动作修复（2026-11-02）：初版 NLA 导出每个轨道仅 2 个相同静止帧，导致只有平移。`desktop-port/godot-spike/modeling/scripts/bake_hulking_glb.py` 直接重写 GLB 有效旋转关键帧，保留原模型、骨架与四组动作；前摇、挥砸、行走和死亡均有真实骨骼姿态变化。
- 行走重定向（2026-11-02）：`hulking_mixamo_big_stride.tres` 使用项目已有 Mixamo `raw_assets/mixamo/run.fbx`（大步幅跑步动作，Mixamo 免费动画许可）重定向至本模型 16 骨骨架，并放慢为重踏节奏；含交替大步、髋部起伏和摆臂，由 `godot/tools/bake_hulking_mixamo_walk.gd` 生成。
- 行为：右臂前摇挥砸，伤害在命中窗口结算，不由普通寄生体即时近战逻辑代替。
