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
- 行为：右臂前摇挥砸，伤害在命中窗口结算，不由普通寄生体即时近战逻辑代替。
