# 非雷械现役武器模型候选 — 2026-11-10

## 范围与核验方式

机主指定 Glock 17 手枪与 SIG MPX 冲锋枪沿用 SPAS-12 的社区现成模型路线。今天完成候选筛选；未下载模型原件、未新增游戏武器、未确定伤害/弹药池/解锁位置。候选不会自动成为正式资产。

本轮通过 Sketchfab 官方公开 API 实时查询搜索结果及逐模型详情。许可证详情明确 `Author must be credited. Commercial use is allowed.`，链接为 [CC-BY 4.0](https://creativecommons.org/licenses/by/4.0/)。这是发布者标注的许可证据，不是对全部上游权属的独立证明。

证据快照为本目录 `08-community-weapon-candidates-2026-11-10.json`，含查询日期、作者、逐模型API URL、许可证、导出统计和描述。GLB统计来自搜索API的 `archives.glb`；详情API的纹理总数可能包含网页预览派生贴图，因此不混作GLB纹理数量。

## 建议进入下一轮下载检查的两个候选

| 用途 | 模型 / 作者 / 原始页面 | 格式与GLB统计 | 动画及适配判断 |
|---|---|---|---|
| Glock 17 首选 | [G17 pistol — MarkkuK](https://sketchfab.com/3d-models/g17-pistol-374ba78efdef4151acd626fb82f81369) | GLB/glTF；24,839三角面；约39.6MB；3张最长4096贴图；Metalness PBR，1材质 | 0段公开动画。优点是材质数少、几何预算适合现有第一人称管线；下载后须检查套筒、弹匣能否独立运动，并复用项目现有持枪/换弹手臂。 |
| SIG MPX 首选 | [Sig Sauer MPX — michalstk11](https://sketchfab.com/3d-models/sig-sauer-mpx-d6e0a8020a7b4a9a876787ec91290022) | GLB/glTF；30,589三角面；约69.8MB；6张最长4096贴图；Metalness PBR，2材质 | 0段公开动画。作者描述为Blender/Substance Painter游戏模型，2套4K材质；下载后检查弹匣、拉机柄、机匣部件与左手支撑位置。 |

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

已为两种目标武器找到可下载、许可明确、提供Godot支持格式的社区候选，推荐先检查MarkkuK的G17与michalstk11的MPX。当前证据覆盖候选可获得性、发布许可和导出元数据；实际尺寸、独立部件、近景外观、握持换弹及Godot导入仍待下载后的技术检查。
