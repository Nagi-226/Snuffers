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

## Hulking Host（2026-11-18 连通骨架修复版）

- 正式派生资产：`hulking_host_repaired.glb`，由项目自有 `hulking_host_animated.glb` 的既有低面数网格生成；原资产保留。
- 来源和权属沿用上面的项目自有 AI 生成资产，无新增第三方资产或运行时依赖。
- 处理脚本：`desktop-port/godot-spike/modeling/scripts/repair_hulking_rig.py`。保留原 19,134 个 GLB 顶点的顺序、14,997 三角面、UV、材质与内嵌贴图字节；将旧模型 yaw 烘焙进几何，统一 Godot -Z 前向并以模型最低点归零。
- 在实际 2.29m 网格上重新放置同名 16 骨并建立髋—躯干、髋—腿—脚、胸—上臂—前臂—手的父子链。2026-11-17 初版按骨段距离生成权重；2026-11-18 复现巨爪后部误分给足骨、最近三骨候选切换造成连通面拉裂后，将巨爪分界移至实际足部前缘，沿原三角邻接平滑权重 100 轮，保留足底和巨爪远端锚点，再连续压缩至每顶点四个影响。原拓扑、UV 和贴图保持。
- 烘焙 idle / walk / attack / death 四组完整局部位移及旋转；行走支撑段配合既有 1.8m/s 物理速度，攻击按 GameConfig 的 1.15s 前摇与 1.0s 恢复生成，不在运行时覆盖为旧扁平骨架轨道。
- 死亡动作保留连通躯干与腿部，以原躯干轴向后横躺，右上臂—前臂—手在肩关节一起收折，避免长爪垫高尸体。每个 60fps 关键帧按全部顶点的真实四影响蒙皮结果烘焙地面接触，保留原背部护甲承重形态；骨长、几何、权重、2.4s 动作长度、死亡碰撞关闭与播放完成后的清理保持。
- 2026-11-18 前版 Godot 实际蒙皮验收 83 项全绿（连通边最大伸长约 2.101 倍），但独立原生画面发现前倾巨爪托住躯干，最低点检查不足以证明自然倒地。补充实际髋、胸（含背甲）、头部质心、下降与横躺检查后，旧资产 94 项中 6 项失败，证据见 `.kimi-tmp/nov18_continue/hulking_death_surface_red.log`。本次后倒收臂的最终验证与原生画面写入本轮交接，不把离线姿态数值记作机主试玩。
- 源 SHA256 `33e8e57aacf9a6fce1f846d78f0eb69b934e373a7f002961b00a301f703939b5`；派生哈希、关节位置、参数及尺寸处理见相邻 `hulking_host_repaired_report.json`。技术与原生皮肤验收记录写入本轮交接，不由资产生成日志代替试玩。
