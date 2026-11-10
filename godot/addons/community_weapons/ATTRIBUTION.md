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
| G17 Pistol - Animated（组合来源） | user77 | https://sketchfab.com/3d-models/g17-pistol-animated-7723ab14e70446ef8e06a134984f287f | CC-BY 4.0 | 2026-11-10 |
| animated pistol（黑色手臂及动画上游） | DJMaesen | https://sketchfab.com/3d-models/animated-pistol-bd896167e7ca44f19597d3afe6a8d83f | CC-BY 4.0 | 2026-11-10 |
| G17 9mm Pistol（组合源包枪模上游） | 3dvachevsky | https://sketchfab.com/3d-models/g17-9mm-pistol-b4136758508c486cadcd96c74d7882b8 | CC-BY 4.0 | 2026-11-10 |

## 本项目改作

- `mpx_tactical.glb`：统一米制比例和枪口方向，装配四份独立配件；按机主反馈将前握把向枪口前移 6cm；保留原拓扑及 UV，十二面独立镜片改为透明材质；贴图最长边缩至 2K。仅为静态模型，没有新增传统武器玩法、照明或红外功能。
- `g17_gen5_olight.glb`：枪身工作长度 0.20m，保留 Frame、Slide、已装 Magazine 和 Olight；衍生版本不包含源包旁边摆放的两只备用弹匣。原装满弹匣网格内单独摆放的膛内展示弹按完整原面分到 Frame，避免换弹时随弹匣漂浮；供弹匣顶端子弹仍随弹匣。保留原拓扑及 UV，贴图最长边缩至 2K。
- `black_pistol_arms.glb`：由 G17 Pistol - Animated 提取黑色手臂，保留原生 60 关节及蒙皮绑定；按 DJMaesen 的帧段拆分射击、换弹、空仓换弹、收枪、举枪和待机。衍生黑布手套调整暗色系数、金属度与粗糙度，去除造成金属反光的 MR 绑定，保留原 Albedo、Normal、AO 贴图及蒙皮数据。源枪渲染件不用于替代本项目枪模，原枪动作节点仍供姿态适配使用。具体处理和校验记录见 `desktop-port/godot-spike/modeling/community_weapons/`。
- 游戏内“资产署名”入口提供以上来源及许可证。本文件及衍生 GLB 内嵌来源信息一并保留。

## 原件保管与重建

下载原件留在 `godot/raw_assets/community_weapons/`，继承 Git 排除规则；该目录的 `.gdignore` 避免原件进入游戏导入队列。Git 只纳入处理后的项目资源及其必要贴图，不提交 Sketchfab 原始下载文件。

MPX / Gen5 重建管线：`desktop-port/godot-spike/modeling/scripts/prepare_community_weapons.py`；原件 SHA256、衍生文件 SHA256、尺寸和配件边界见 `desktop-port/godot-spike/modeling/community_weapons/prepared_assets.json`。
