# 01 · 角色与动画资产调研（士兵角色 + 动画）

> 调研人：角色与动画资产调研员 · 调研日期：2026-07-15（UTC+8）
> 目标项目：「废墟突围」Godot 4.6.2 原生重制版 · 低多边形（low-poly）夜战射击
> 需求覆盖：现代军事风 3 类敌人（步兵/机枪手/狙击手，可同模换色换装备）、玩家第一人称手部/武器持握（可选）、角色动画（待机/行走/奔跑/瞄准/射击/死亡/趴下）

---

## 〇、结论先行

**首选组合（全部 CC0、glTF 直拖 Godot 4、中国大陆直连可达）：**

1. **Quaternius — Universal Animation Library 2（UAL2）+ Universal Base Characters**：动画库与角色共用同一副 Humanoid Rig，**免重定向**；130+ 动画含持械 combat、移动、僵尸/倒地；官方导出经 Godot 实测。**模型+动画一站解决，是本调研的最优解。**
2. **Quaternius — Toon Shooter Game Kit**：射击游戏专用包，角色自带 17 个动画 + 敌人 + 环境件，toon 低模，与夜战卡通渲染适配。
3. **KayKit — Character Animations（133 个动画，含瞄准/射击/装填/蹲伏/爬行/躺倒）+ KayKit 角色包（Adventurers / Skeletons）**：走 **GitHub 组织直下**（绕开被墙的 itch.io），动画量最大、覆盖面最接近需求清单。

**备选 / 补充：**

4. **Kenney — Blocky Characters**（CC0）：原型期占位、动画测试用。
5. **Mixamo**（Adobe 免费，可商用但**禁止再分发原始文件**）：补齐 UAL2/KayKit 缺的战术动作（趴下、持枪瞄准细化）；FBX 需经 FBX2glTF / Blender 转 glTF。

**网络实况（2026-07-15 实测）**：quaternius.com、kenney.nl、github.com、kaylousberg.com、mixamo.com、opengameart.org **可达**；itch.io（含全部子域）、poly.pizza、godotengine.org（含 AssetLib API）、mesh2motion.org **不可达**。

---

## 一、中国大陆网络可达性实测

测试方法：`curl -L` 跟随跳转，连接超时 8–10s，失败项二次复测确认。测试时间 2026-07-15 20:46–21:00（UTC+8）。

| 站点 | 结果 | 说明 |
|---|---|---|
| quaternius.com | ✅ HTTP 200 | 官网直连，无需登录即可下载免费层 |
| kenney.nl | ✅ HTTP 200 | 官网直连，无需登录 |
| github.com（含 api.github.com / raw） | ✅ HTTP 200 | KayKit / GDQuest / Mesh2Motion 源码分发通道 |
| kaylousberg.com | ✅ HTTP 200 | KayKit 作者官网（但下载按钮多跳转 itch.io，见风险节） |
| www.mixamo.com | ✅ HTTP 200 | 需 Adobe 账号登录使用 |
| opengameart.org | ✅ HTTP 200 | 备选 CC0 源 |
| itch.io / *.itch.io | ❌ HTTP 000 | KayKit、Quaternius 的 itch 镜像均不可达 |
| poly.pizza | ❌ HTTP 000 | 低模聚合站，二次复测仍失败 |
| godotengine.org（含 /asset-library、AssetLib API） | ❌ HTTP 000 | **连带影响：Godot 编辑器内 AssetLib 在本网络下无法浏览/下载** |
| mesh2motion.org | ❌ HTTP 000 | 开源 Mixamo 替代品（可自托管，见 2.7） |

---

## 二、逐项资产调研

### 2.1 Quaternius（CC0）⭐ 主推源

平台直达 ✅，全部 CC0，免费层约为完整包的 60–70%（完整层/Source 层走 Patreon，同样 CC0，含 .blend 源文件与三引擎工程）。通用格式：glTF + FBX + OBJ。

| # | 资产包 | URL | 许可证 | 格式 | 骨骼/动画 | 规模 | 风格 | Godot 4 导入说明 | 可达性 |
|---|---|---|---|---|---|---|---|---|---|
| 1 | **Universal Animation Library 2** | https://quaternius.com/packs/universalanimationlibrary2.html | CC0 | glTF/FBX/OBJ；Source 层含 .blend | 通用 Humanoid Rig，**130+ 动画**（持械连击、跑酷移动、僵尸步态、日常交互等） | 动画库 | 低模通用 | 官方提供**经 Godot 实测的导出**，glTF 拖入即用；动画按 Humanoid 骨骼命名，可直接进 AnimationTree | ✅ |
| 2 | Universal Animation Library（v1） | https://quaternius.com/packs/universalanimationlibrary.html | CC0 | glTF/FBX/OBJ | 同一 Humanoid Rig，与 v2 互补 | 动画库 | 低模通用 | 同上 | ✅ |
| 3 | **Universal Base Characters** | https://quaternius.com/packs/universalbasecharacters.html | CC0 | FBX + glTF；Source 含 .blend 与 Godot 4.3 工程 | **已绑骨（Humanoid Rig），明确兼容 UAL**；20 发型混搭、肤色/眼色可调 | 6 个基础体型（男/女 × 常规/少年/超级英雄），**平均 13k 三角面** | 风格化中低模（比典型 low-poly 略高面数） | glTF 直拖；与 UAL2 同 rig，**免重定向**；"换色"可经材质/Shader 参数实现 | ✅ |
| 4 | **Toon Shooter Game Kit** | https://quaternius.com/packs/toonshootergamekit.html | CC0 | FBX/OBJ/glTF/.blend | **角色含 17 个动画** + 敌人 + 环境件（2022-12 发布） | 大型综合包 | **卡通低模**，射击题材 | glTF 直拖；一包凑齐"角色+动画+敌人+武器雏形" | ✅ |
| 5 | Ultimate Modular Characters | https://quaternius.com/packs/ultimatemodularcharacters.html | CC0 | glTF/FBX/OBJ | 模块化角色（拼装思路） | 模块件 | 低模 | 适合"同模换装备"思路的拼装件来源 | ✅ |
| 6 | Modular Character Outfits - Fantasy | https://quaternius.com/packs/modularcharacteroutfitsfantasy.html | CC0 | glTF/FBX | 已绑骨、可重定向（官网标注 Rigged / Retargetable） | 服装模块 | 低模（奇幻向） | 装备/外观模块参考；题材偏奇幻 | ✅ |

> 备注：官网另有 `animatedmen/animatedwomen/animatedzombie/easyenemy` 等单角色动画包（URL 已验证存在），可作散件补充。

### 2.2 KayKit（CC0，作者 Kay Lousberg）

itch.io 被墙 → **改用 GitHub 组织 `KayKit-Game-Assets` 直下**（API 已核实全部仓库在线，LICENSE.txt 为 CC0 1.0 Universal）；作者官网 kaylousberg.com 可达但下载按钮跳 itch.io。仓库内除模型外还附 `addons/` 导入辅助目录与 Unity/Godot 示例。

| # | 资产包 | URL | 许可证 | 格式 | 骨骼/动画 | 规模 | 风格 | Godot 4 导入说明 | 可达性 |
|---|---|---|---|---|---|---|---|---|---|
| 7 | **KayKit Character Animations** | https://kaylousberg.com/game-assets/character-animations （下载跳 itch.io；可经 GitHub 组织/作者渠道获取） | CC0 | FBX + glTF | **133 个人形动画**：待机/受击/死亡/生成/行走/奔跑/跳跃/**爬行**/潜行/闪避/**蹲伏**、近战全系、**远程：射击/瞄准/装填（单手+双手、弓、法术）**、表情、躺倒；分 Rig_Medium / Rig_Large 两套骨骼 | 动画库 | 低模通用 | glTF 直拖；动画与 KayKit 角色同 rig **免重定向**；跨 rig 用 Godot 4 内置重定向 | ⚠️ 官网可达，itch.io 下载点不可达 → 走 GitHub |
| 8 | KayKit Character Pack: Adventurers | https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0 | CC0（LICENSE.txt 已核实） | FBX + glTF | 4 个角色全绑骨+动画（README 标注 75 动画），25+ 武器配件（剑/盾/斧/弩/法杖） | 单角色约 1–3k 三角面（低模优化，移动端可用） | 低模奇幻（骑士/法师等） | glTF 直拖；单张 1024² 渐变图集可压到 128²；仓库含 Godot 示例 | ✅（GitHub） |
| 9 | KayKit Character Pack: Skeletons | https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Skeletons-1.0 | CC0（LICENSE.txt 已核实） | FBX + glTF | 骷髅敌人，绑骨+专用动画（待机/行走/受击/死亡/生成） | 低模 | 低模奇幻敌人 | 可作敌人占位/特殊敌人；题材非军事 | ✅（GitHub） |

### 2.3 Kenney（CC0）

| # | 资产包 | URL | 许可证 | 格式 | 骨骼/动画 | 规模 | 风格 | Godot 4 导入说明 | 可达性 |
|---|---|---|---|---|---|---|---|---|---|
| 10 | Blocky Characters（v2.0 完全重制） | https://kenney.nl/assets/blocky-characters | CC0（页面已核实） | Kenney 3D 惯例：glTF/OBJ/FBX | 页面标注含 Animation，20 个文件 | 极低面（方块人） | 方块/体素风（Roblox 感） | glTF 直拖；风格与"现代军事"差距大，定位**原型占位/动画管线验证** | ✅ |

### 2.4 Poly.pizza（低模聚合站）

| 平台 | URL | 许可证 | 可达性 | 结论 |
|---|---|---|---|---|
| Poly.pizza | https://poly.pizza | **CC0 / CC-BY 混杂**，逐模型标注（Quaternius、KayKit 作品大量收录） | ❌ 二次实测 HTTP 000 | **本网络不可用**。其上 CC0 内容可经 quaternius.com / GitHub 同源获取，不构成实质损失；CC-BY 内容需逐条署名，优先级降低 |

### 2.5 Mixamo（Adobe 免费动画库 + 自动绑骨）

| 平台 | URL | 许可证/条款 | 格式 | 骨骼/动画 | Godot 4 导入说明 | 可达性 |
|---|---|---|---|---|---|---|
| Mixamo | https://www.mixamo.com | **非 CC0**：Adobe 服务条款——免费、**可商用、免署名**；但①**禁止以任何形式再分发原始角色/动画文件**（不得进公开仓库、不得做成资产包转售/分享，必须"锁进"游戏成品）②禁止用于训练 ML 模型③条款注明可能变更，发布前需复核 mixamo.com/terms | 下载 FBX / FBX(for Unity) / Collada(DAE) | 自带数百个写实动捕动画（**待机/行走/奔跑/瞄准/射击/死亡/趴下爬行**全覆盖），支持上传自有模型**自动绑骨** | FBX 需中转：**FBX2glTF** 或 Blender 导入→导出 glTF；骨骼前缀 `mixamorig:`，Godot 4 内建 BoneMap 做一次映射即可复用 | ✅ HTTP 200（需 Adobe 账号） |

### 2.6 Godot 官方 Asset Library

| 平台 | URL | 可达性 | 结论 |
|---|---|---|---|
| Godot Asset Library（网页 + 编辑器内 AssetLib） | https://godotengine.org/asset-library | ❌ 网页与 API 均 HTTP 000 | **本网络不可用**（编辑器内 AssetLib 同样走该域名，会被连带阻断）。替代路径：AssetLib 条目多数托管于 GitHub，可经 GitHub 搜索同名仓库获取；或走代理。**本次未能在线核实具体条目，不臆造清单** |

GitHub 上已核实的 Godot 官方/半官方人物条目：

| # | 资产 | URL | 许可证 | 说明 | 可达性 |
|---|---|---|---|---|---|
| 11 | GDQuest Godot 3D Mannequin（角色+角色控制器） | https://github.com/gdquest-demos/godot-3d-mannequin （原 GDQuest 组织，已迁移，1.1k★） | MIT（书籍与仓库惯例；GitHub API 标 NOASSERTION，**使用前请开仓库 LICENSE 复核**） | 开源 3D 人物 + 控制器参考实现；最后提交停在 2021-08（Godot 3.x 时代），**宜作参考不宜直接用** | ✅ |

### 2.7 补充发现：Mesh2Motion（开源 Mixamo 替代）

| 平台 | URL | 许可证 | 说明 | 可达性 |
|---|---|---|---|---|
| Mesh2Motion | https://mesh2motion.org （源码在 GitHub） | CC0（应用与动画，含 Quaternius 人形动画） | 浏览器内自动绑骨 + 150+ 动画库 + 重定向 + **导出 GLB**；支持导入 GLB/glTF/DAE/FBX | ❌ 站点不可达；**开源自托管可行**（GitHub 可达），值得作为 Mixamo 的离线替代方案评估 |

---

## 三、需求覆盖度对照

| 需求 | UAL2 + Base Characters | Toon Shooter Kit | KayKit 动画+角色 | Mixamo |
|---|---|---|---|---|
| 待机 Idle | ✅ | ✅ | ✅ | ✅ |
| 行走/奔跑 | ✅ | ✅ | ✅ | ✅ |
| 瞄准/射击 | ✅（armed combat 系） | ✅（17 动画内含） | ✅（1h/2h 射击+瞄准+装填） | ✅ |
| 死亡 | ✅ | ✅ | ✅ | ✅ |
| 趴下/匍匐 | ⚠️ 未见明示（有倒地/僵尸系可代） | ⚠️ 未见明示 | ✅（Crawling / Lying Down） | ✅（Prone 系） |
| 3 类敌人同模换色换装备 | ⚠️ 换色易（材质参数），军事装备需自制/拼装 | ⚠️ 有现成敌人但卡通 | ⚠️ 奇幻题材 | ❌（无模块化换装） |
| 第一人称手部/持握 | ❌ | ❌ | ❌ | ⚠️ 有持枪上身动画，需裁手臂方案 |
| 许可证安心度 | ✅ CC0 | ✅ CC0 | ✅ CC0 | ⚠️ 可商用但禁再分发源文件 |

---

## 四、Godot 4 动画重定向（Retarget）可行性评估

**结论：可行，且 4.x 已内置完整工具链；本项目首选路径甚至可以绕开重定向。**

1. **内置能力**：Godot 4 在 glTF/FBX 的 Advanced Import Settings 中提供 **Retarget** 面板，基于 `SkeletonProfileHumanoid` + `BoneMap`（骨骼名映射表）做人形动画重定向；4.3 起对 Rest Pose 处理、骨骼映射 UI 有实质改进，4.6.2 已成熟。映射表可保存复用。
2. **免重定向路径（推荐）**：UAL2 动画与 Universal Base Characters 共用同一副 Humanoid Rig、KayKit 动画与 KayKit 角色共用 Rig_Medium/Large——**同生态内零重定向**，动画直接进 AnimationPlayer/AnimationTree。这也是首选组合的最大工程优势。
3. **跨生态路径**：Mixamo（`mixamorig:` 前缀骨骼）→ Godot 内建 BoneMap 手动映射一次后复用；或经 Blender（Rokoko Retarget / Auto-Rig Pro 等插件）中转再导出 glTF。
4. **低模注意事项**：低模角色常无手指/脚趾骨，BoneMap 只映射已存在的骨骼即可，缺失骨自动忽略，不影响主体动作；Quaternius/KayKit 的 rig 均为标准人形层级，实测社区反馈在 Godot 4 重定向成功率高。

---

## 五、风险与缺口

1. **"现代军事"题材缺口（最大内容风险）**：CC0 低模生态中没有现成的现代士兵包——KayKit 偏奇幻、Quaternius Toon Shooter 偏卡通、Universal Base Characters 是便装体型。落地路线：用 Universal Base Characters 做底模 + 材质换色（迷彩/阵营色）+ 自制低模装备件（头盔/背心/枪械，可并入 03 号武器调研的 Quaternius `ultimategun`/`scifimodularguns` 包），接受"风格化准军事"而非写实军事。
2. **第一人称手部/武器持握动画缺口**：所有 CC0 包均无 FP 手臂+持握动画。可行方案：Mixamo 取步枪瞄准/射击上身动画 → 裁切为"仅手臂+枪"的 FP  rigs（常见 indie 做法）；或程序化摆动（沿用现有 Three.js 版思路）。预计需要 1–2 天手工调整，列为制作任务而非资产采购。
3. **网络与分发风险**：itch.io / poly.pizza / godotengine.org 不可达——KayKit 务必走 GitHub 组织克隆；Godot AssetLib 需代理或 GitHub 镜像。Mixamo 法律红线：**原始 FBX/动画文件不得提交进本仓库**（尤其公开仓库），只能烘焙进游戏包体；.gitignore 需排除 Mixamo 源文件目录，发布前复核 Adobe 最新条款。

---

## 附：引用来源（本轮实际访问）

- [Quaternius 官网及包页](https://quaternius.com/)：[UAL2](https://quaternius.com/packs/universalanimationlibrary2.html)、[Universal Base Characters](https://quaternius.com/packs/universalbasecharacters.html)、[Toon Shooter Game Kit](https://quaternius.com/packs/toonshootergamekit.html)、[UAL v1](https://quaternius.com/packs/universalanimationlibrary.html)、[Ultimate Modular Characters](https://quaternius.com/packs/ultimatemodularcharacters.html)
- [KayKit Character Animations — kaylousberg.com](https://kaylousberg.com/game-assets/character-animations)、[KayKit Adventurers — GitHub](https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0)、[KayKit Skeletons — GitHub](https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Skeletons-1.0)
- [Kenney Blocky Characters](https://kenney.nl/assets/blocky-characters)
- [gdquest-demos/godot-3d-mannequin — GitHub](https://github.com/gdquest-demos/godot-3d-mannequin)
- [Mixamo 许可 FAQ — Adobe Community](https://community.adobe.com/questions-696/mixamo-faq-licensing-royalties-ownership-eula-and-tos-589400)、[LicenseOrg Mixamo 摘要](https://licenseorg.com/guide/3d-assets/mixamo)
- [Jettelly：UAL2 跨引擎报道](https://jettelly.com/blog/universal-animation-library-2-a-cross-engine-animation-pack-with-a-universal-humanoid-rig)、[Mesh2Motion 官网](https://mesh2motion.org/)、[GameFromScratch：Mesh2Motion 介绍](https://gamefromscratch.com/mesh2motion-free-open-source-animation-app/)
- 网络可达性：2026-07-15 本机 `curl` 实测（见第一节）
