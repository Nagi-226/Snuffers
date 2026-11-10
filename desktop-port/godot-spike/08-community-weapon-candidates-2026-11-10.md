# 非雷械现役武器模型候选 — 2026-11-10

## 范围与核验方式

机主指定 Glock 17 手枪与 SIG MPX 冲锋枪沿用 SPAS-12 的社区现成模型路线。今天完成候选筛选；未下载模型原件、未新增游戏武器、未确定伤害/弹药池/解锁位置。候选不会自动成为正式资产。

本轮通过 Sketchfab 官方公开 API 实时查询搜索结果及逐模型详情。许可证详情明确 `Author must be credited. Commercial use is allowed.`，链接为 [CC-BY 4.0](https://creativecommons.org/licenses/by/4.0/)。这是发布者标注的许可证据，不是对全部上游权属的独立证明。

证据快照为本目录 `08-community-weapon-candidates-2026-11-10.json`，含查询日期、作者、逐模型API URL、许可证、导出统计和描述。GLB统计来自搜索API的 `archives.glb`；详情API的纹理总数可能包含网页预览派生贴图，因此不混作GLB纹理数量。

## 建议进入下一轮下载检查的两个候选

**机主追加裁决（同日）**：已同意使用下列MarkkuK的G17。MPX须继续筛选带全息瞄具、前握把及红外/手电配件的版本；下列michalstk11模型现仅保留为基础枪身候选，不能视为满足完整配件需求。详细结果见末节。

| 用途 | 模型 / 作者 / 原始页面 | 格式与GLB统计 | 动画及适配判断 |
|---|---|---|---|
| Glock 17 首选 | [G17 pistol — MarkkuK](https://sketchfab.com/3d-models/g17-pistol-374ba78efdef4151acd626fb82f81369) | GLB/glTF；24,839三角面；约39.6MB；3张最长4096贴图；Metalness PBR，1材质 | 0段公开动画。优点是材质数少、几何预算适合现有第一人称管线；下载后须检查套筒、弹匣能否独立运动，并复用项目现有持枪/换弹手臂。 |
| SIG MPX 基础枪身候选 | [Sig Sauer MPX — michalstk11](https://sketchfab.com/3d-models/sig-sauer-mpx-d6e0a8020a7b4a9a876787ec91290022) | GLB/glTF；30,589三角面；约69.8MB；6张最长4096贴图；Metalness PBR，2材质 | 0段公开动画。作者描述为Blender/Substance Painter游戏模型，2套4K材质；下载后检查弹匣、拉机柄、机匣部件与左手支撑位置。 |

以上两份实时标注 `isDownloadable=true`、CC-BY 4.0。可在满足署名、保留许可链接、标明修改的条件下用于商业游戏；正式选择时还需核对下载包说明与上游来源。页面标为G17，是否精确对应希望使用的Glock 17代际/外形需下载及机主外观确认。

**尺寸状态**：官方公开元数据没有提供可靠的米制包围盒或实枪比例，本轮未下载，故两份实际长度/原点/枪口方向均未测量。不能将页面预览比例当成Godot米制尺寸，不能宣称已导入或已实机适配。

## 备选

| 用途 | 模型 / 作者 / 原始页面 | 格式与GLB统计 | 取舍 |
|---|---|---|---|
| Glock 动画参考 | [G17 Pistol - Animated — user77](https://sketchfab.com/3d-models/g17-pistol-animated-7723ab14e70446ef8e06a134984f287f) | GLB/glTF；60,167三角面（整包，含手臂）；约128.5MB；27张最长4096贴图；1段动画 | 发布者明确武器来自 [3dvachevsky](https://sketchfab.com/3d-models/g17-9mm-pistol-b4136758508c486cadcd96c74d7882b8)，手臂/动画来自 [DJMaesen](https://sketchfab.com/3d-models/animated-pistol-bd896167e7ca44f19597d3afe6a8d83f)。本轮已核对武器上游CC-BY；动画上游尚未逐包核验，正式使用前必须补齐。不能只署名user77。 |
| SIG MPX 低开销参考 | [Low-Poly Sig MPX — TastyTony](https://sketchfab.com/3d-models/low-poly-sig-mpx-ac70a5fcfff348168d6f3ea2919522c7) | GLB/glTF；11,145三角面；约1.5MB；GLB纹理数0；0段动画；CC-BY 4.0 | 文件小，适合遗留拾取物/远景；缺少写实贴图信息，第一人称近景需外观验证。部件和尺寸未测。 |

初筛还发现 Nikitos 的 [Glock-17](https://sketchfab.com/3d-models/glock-17-aeb171380b2b490c80aa04b4ee1a9366)：3,576面、0贴图、23材质、1整段射击/换弹动画，CC-BY 4.0。作者自己称其为 `Glock Style`，作为低模动画参考保留，不将其外形等同于写实Glock 17。其他Glock结果中存在 `Free Standard` 或不可下载/无许可标注，未纳入本轮CC-BY首选。

Max的MPX虽带CC-BY标签，描述另要求告知作者用途；本轮没有联系作者，故不列为首选。明确标为MCX、MPX-SD或拆散展示包的结果也未当成基础MPX直接推荐。

## 正式接入前的检查顺序

1. 从官方页面下载，保存许可证/包内readme及SHA256；原始Sketchfab文件只放排除Git的工作区，按SPAS-12方式输出游戏用资产。
2. 检查真实网格与材质：枪口朝向、米制长度、原点；弹匣/套筒/拉机柄能否分离；UV/PBR/透明件及瞄具通光。首选两份的部件分离情况目前均未证实。
3. 沿用GLB本地处理与现有手臂管线；考虑将4K贴图降至2K、只保留游戏所需贴图和部件。此处是后续处理建议，不是本轮已完成的转换。
4. 用Godot 4.6.2实际导入，拍第一人称/拾取物多视图，验证握持、套筒/供弹动作及原换弹动画重定向。模型有动画不意味着现有双臂自动兼容。
5. 在 `godot/assets/models/weapons/ATTRIBUTION.md` 登记正式输出、完整作者链、原URL、CC-BY4.0、下载日期、哈希、改动；添加游戏内署名后才发布含这些资产的包体。
6. 由机主决定武器数值、传统弹药是否共池、领装与后续关卡位置，再冻结Config/State/Events并按模块接入。今天不推断这些业务规则。

## 本轮结论

已为两种目标武器找到可下载、许可明确、提供Godot支持格式的社区候选。MarkkuK的G17已获机主同意；MPX配件要求按下方追加筛选执行。当前证据覆盖候选可获得性、发布许可和导出元数据；实际尺寸、独立部件、近景外观、握持换弹及Godot导入仍待下载后的技术检查。

## MPX完整配件追加筛选（同日）

### 现成整枪候选

| 模型 / 作者 | 已核对配件 | 可获得性与缺口 |
|---|---|---|
| [Low Poly Tactical SIG MPX — untoucheddev](https://sketchfab.com/3d-models/low-poly-tactical-sig-mpx-d2866df6d1b54735bb7621ac2bbca64c) | 官方预览可见全息式瞄具、斜前握把、前部激光模块及红色可见光束 | 20,702显示三角面；目前 `isDownloadable=false`、许可证为空。作者公开简介只说接受委托，没有下载商店链接。本轮未联系作者。模块是否包含红外发射/白光手电未获证实；仅作外观参考，不能直接入库。 |
| [Low Poly MPXSD — samanthacford](https://sketchfab.com/3d-models/low-poly-mpxsd-f1a48dc433354e018e569d5d695567ab) | 作者明确说明全息镜、侧置激光、一体消音器；官方预览与描述一致 | 可下载、CC-BY4.0，显示7,206面，0段动画。预览未见独立前握把，红外/白光未证实；是带消音结构的低模改型，不是配件全部齐全的原始MPX。 |
| [Sig Sauer MPX + EOTech XPS — Reil](https://sketchfab.com/3d-models/sig-sauer-mpx-eotech-xps-8a24b0a997d54826ba1b665ec85f3b38) | 作者明确EOTech XPS2，预览可见 | 当前不可下载、无明确许可；预览未见完整前握把/光学模块组合，不列为可入库首选。 |

查阅了官方MPX分页结果，并用tactical/holographic/PEQ关键词补查；没有据此宣称所有社区均无符合模型。以上是本轮能够核实的结果。红色可见激光不是红外功能的证据，模型外观也不代表游戏内已实现发光/照明。

### 可获得的社区配件组合方案（待机主批准加工）

以原michalstk11的MPX本体为基础，下面四份官方API均标注可下载、CC-BY4.0及GLB/glTF导出。它们是分别发布的现成模型，本轮未下载或装配成完整武器。

| 配件 | 模型 / 作者 | 导出统计与限制 |
|---|---|---|
| 全息镜 | [EOTECH HWS EXPS 3 — Sambit_Raut](https://sketchfab.com/3d-models/eotech-hws-exps-3-04d1452515134866b8a97c3e7cb9a18e) | 6,889GLB面、Metalness PBR；4张最长4K。须实测镜片与准星通光。 |
| 前握把 | [Foregrip — elitej1gaming](https://sketchfab.com/3d-models/foregrip-52781078a99c4e55934dab26a998875f) | 11,924GLB面、Metalness PBR；3张最长4K。实际接口、比例与左手握持待测。 |
| 红外模块 | [low-poly AN/PEQ 15 — D_U](https://sketchfab.com/3d-models/low-poly-anpeq-15-522f6a04c34946dbb168022187645c1a) | 3,552GLB面、2材质、0贴图。作者明确红外激光/可见激光/红外照明的实物规格；这不代表模型或游戏内已经实现这些功能。需对齐写实枪身的材质风格。 |
| 白光手电 | [SureFire M600DF — mbvisuals1](https://sketchfab.com/3d-models/surefire-m600df-game-ready-flashlight-c04c7a9b2f8346bd90c3938b0af8024a) | 12,146GLB面、Metalness PBR；导出统计17张最长2K，作者描述1套4K原贴图，两者口径分开记录。灯与导轨连接、开关和照明行为未适配。 |

本体与四配件公开GLB面数合计65,100；这是未优化的元数据加总，不是已完成模型或性能实测。后续须实测导轨、安装点、米制尺寸、配件互相遮挡、全息瞄准光轴、手臂与换弹空间；统一贴图预算并逐项署名。不使用混元3D生成这些模型。

**待决定路线**：A，使用社区MPX本体与上述现成配件组装完整配置；B，以untoucheddev的完整外观为目标，先取得其模型和明确商用授权。本轮只记录方案，不自动下载/装配或发送授权申请，也不新增武器玩法。
