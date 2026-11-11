# 社区武器与黑色第一人称手臂

引入日期：2026-11-10。以下条目均采用 [CC-BY 4.0](https://creativecommons.org/licenses/by/4.0/)，允许商用及修改，须保留作者、来源、许可证与改作说明。

| 名称 | 作者 | 来源 | 许可证 | 日期 |
|---|---|---|---|---|
| Sig Sauer MPX | michalstk11 | https://sketchfab.com/3d-models/sig-sauer-mpx-d6e0a8020a7b4a9a876787ec91290022 | CC-BY 4.0 | 2026-11-10 |
| EOTech HWS EXPS 3 | Sambit_Raut | https://sketchfab.com/3d-models/eotech-hws-exps-3-04d1452515134866b8a97c3e7cb9a18e | CC-BY 4.0 | 2026-11-10 |
| Foregrip | elitej1gaming | https://sketchfab.com/3d-models/foregrip-52781078a99c4e55934dab26a998875f | CC-BY 4.0 | 2026-11-10 |
| Low Poly AN/PEQ 15 | D_U | https://sketchfab.com/3d-models/low-poly-anpeq-15-522f6a04c34946dbb168022187645c1a | CC-BY 4.0 | 2026-11-10 |
| SureFire M600DF | mbvisuals1 | https://sketchfab.com/3d-models/surefire-m600df-game-ready-flashlight-c04c7a9b2f8346bd90c3938b0af8024a | CC-BY 4.0 | 2026-11-10 |
| G17 Gen5 + Olight | 8sianDude | https://sketchfab.com/3d-models/g17-gen-5-handgun-olight-nsw-police-force-0200c248eba14385ad2bee8d4dc4e586 | CC-BY 4.0 | 2026-11-10 |
| Weapon lights — X400 pistol light+laser | shirioko | https://sketchfab.com/3d-models/weapon-lights-d8315946217a40b38808353a7ce81520 | CC-BY 4.0 | 2026-11-11 |
| G17 Pistol - Animated（组合来源） | user77 | https://sketchfab.com/3d-models/g17-pistol-animated-7723ab14e70446ef8e06a134984f287f | CC-BY 4.0 | 2026-11-10 |
| animated pistol（黑色手臂及动画上游） | DJMaesen | https://sketchfab.com/3d-models/animated-pistol-bd896167e7ca44f19597d3afe6a8d83f | CC-BY 4.0 | 2026-11-10 |
| G17 9mm Pistol（组合源包枪模上游） | 3dvachevsky | https://sketchfab.com/3d-models/g17-9mm-pistol-b4136758508c486cadcd96c74d7882b8 | CC-BY 4.0 | 2026-11-10 |

## 本项目改作

- `mpx_tactical.glb`：统一米制比例和枪口方向，装配四份独立配件；按机主反馈将前握把向枪口前移 6cm；保留原拓扑及 UV，十二面独立镜片改为透明材质；贴图最长边缩至 2K。仅为静态模型，没有新增传统武器玩法、照明或红外功能。
- `g17_gen5_olight.glb`：枪身工作长度 0.20m，保留 Frame、Slide、已装 Magazine 和 Olight；衍生版本不包含源包旁边摆放的两只备用弹匣。原装满弹匣网格内单独摆放的膛内展示弹按完整原面分到 Frame，避免换弹时随弹匣漂浮；供弹匣顶端子弹仍随弹匣。保留原拓扑及 UV，贴图最长边缩至 2K。
- `black_pistol_arms.glb`：由 G17 Pistol - Animated 提取黑色手臂，保留原生 60 关节及蒙皮绑定；按 DJMaesen 的帧段拆分射击、换弹、空仓换弹、收枪、举枪和待机。衍生黑布手套调整暗色系数、金属度与粗糙度，去除造成金属反光的 MR 绑定，保留原 Albedo、Normal、AO 贴图及蒙皮数据。源枪渲染件不用于替代本项目枪模，原枪动作节点仍供姿态适配使用。具体处理和校验记录见 `desktop-port/godot-spike/modeling/community_weapons/`。
- 游戏内“资产署名”入口提供以上来源及许可证。本文件及衍生 GLB 内嵌来源信息一并保留。
- `mpx_reticle_red.png`（2026-11-11）：从已登记的 Sambit_Raut EOTech HWS EXPS 3 准星纹理（`mpx_tactical.glb` 的 Image9 / `crosshair`）提取透明红色改作，沿用 CC-BY 4.0 及上表作者/URL；本项目 Codex 处理。保留2048×2048尺寸与UV，RGB设为红色，alpha为 `max(0,r-max(g,b))`，去掉原RGB(188,188,188)不透明灰底并保留原红色点/环及抗锯齿覆盖。源GLB与贴图保持。源GLB SHA256 `70ddaf91893ec94b4aecef5cd03ab86eaadda1fdc98c06ee68aa45de7e85995f`，衍生PNG SHA256 `ec45604c7e703b48534524ef366b902b391df8f0166fa9ea2973f060ce1f9589`；离线步骤与报告位于 `.kimi-tmp/nov11_g17_mpx/derive_mpx_reticle.py`、`mpx_reticle_derivation.json`，游戏运行时只加载派生PNG。

## 原件保管与重建

- `x400_red_white.glb`（2026-11-11）：机主下载并提供`weapon_lights.glb`，官方模型API核作者shirioko、可下载、CC-BY4.0允许商用/改作。仅提取X400独立网格（264三角面），保留源材质、UV与拓扑；烘焙原FBX导出坐标变换，枪口为-Z，以真实世界AABB中心归零，尺寸37×44×90mm。原四灯整包不入库，放在git排除的`raw_assets/community_weapons/weapon_lights_20261111/`；提取GDScript及真实尺寸报告同目录。原件SHA256 `eef2c72cd8367e099f03ce2d2794ba125d5ed7a54b4a78f0be5121463f5ab2db`。用于G17红激光+白光组合模块，替换实例中的PL-2显示，不修改原G17 GLB。

MPX/G17/黑臂下载原件留在 `godot/raw_assets/community_weapons/`，继承 Git 排除规则；该目录的 `.gdignore` 避免原件进入游戏导入队列。X400整包和提取脚本另存仓库根的 `raw_assets/community_weapons/weapon_lights_20261111/`，同样已核Git排除且在Godot项目目录外。Git只纳入处理后的项目资源及其必要贴图，不提交Sketchfab原始下载文件。

MPX / Gen5 重建管线：`desktop-port/godot-spike/modeling/scripts/prepare_community_weapons.py`；原件 SHA256、衍生文件 SHA256、尺寸和配件边界见 `desktop-port/godot-spike/modeling/community_weapons/prepared_assets.json`。
