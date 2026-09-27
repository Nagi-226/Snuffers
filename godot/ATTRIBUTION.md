# ATTRIBUTION — 资产署名台账

> 依据仓库根 `AGENTS.md` 约束 #7（资产法律卫生）：
>
> - **每个入库资产必须登记本表**，字段：名称 / 作者 / URL / 许可证 / 日期。
> - Mixamo、Sketchfab、PolyPack 的**原始文件禁止提交进 git 仓库**（`.gitignore` 已排除 `*.fbx` 等格式与 `raw_assets/` 目录），只能烘焙进包体。
> - CC-BY 类资产需在游戏内署名（结算/关于界面）。
> - 第三方代码/插件一律进 `godot/addons/`，同样登记本表。

> **盘点范围（2026-08-01 补登）**：`godot/assets/` 全部第三方资产 + `godot/addons/` 第三方插件。
> `godot/assets/textures/` 当前为空，无独立字体/模型入库；条目格式对齐 `godot/addons/jeh3no_fps_weapon_system/ATTRIBUTION.md` 子台账。

---

## 一、第三方代码/插件（godot/addons/）

### 1. Godot Simple FPS Weapon System

| 项 | 值 |
|---|---|
| 名称 | Godot Simple FPS Weapon System |
| 作者 | Jeh3no（GitHub） |
| 来源 URL | https://github.com/Jeh3no/Godot-simple-FPS-weapon-system |
| 许可证 | MIT（见 `godot/addons/jeh3no_fps_weapon_system/LICENSE`） |
| 引入日期 | 2026-07-20（Sprint 2，W2 火力蜂） |
| 引入目的 | **仅结构评估借鉴**，不接入业务代码（Sprint 2 派单口径） |
| 详细子台账 | `godot/addons/jeh3no_fps_weapon_system/ATTRIBUTION.md`（含借鉴点说明） |

**随插件自带的第三方演示资源**（仅供其 demo 场景自洽，spike 业务场景不引用，来源见插件 `README.md` Credits 段）：

| 名称 | 作者 | URL | 许可证 | 日期 |
|------|------|-----|--------|------|
| Kenney Prototype Textures | Kenney（Godot 资产库上传者 Calinou） | https://godotengine.org/asset-library/asset/781 | CC0（见插件子台账说明） | 2026-07-20（随插件引入） |
| Free Low Poly Weapons Pack（武器模型与贴图，RPG 除外） | amaraha | https://amaraha.itch.io/free-low-poly-weapons-pack | 来源待考（插件内未注明许可证，G4 美术阶段补查） | 2026-07-20（随插件引入） |
| Ammo Canister 模型与贴图 | Stephen Yoshimura（经 Poly Pizza 分发） | https://poly.pizza/m/b2_n3tmq02h | CC-BY（插件 README 注明，**需游戏内署名**） | 2026-07-20（随插件引入） |
| Low Poly RPG-7 模型与贴图 | 来源待考（Sketchfab 页面，插件 README 未署名作者/许可证，G4 美术阶段补查） | https://sketchfab.com/3d-models/low-poly-rpg-7-de967b52c9794d2995d4606749fcdff7 | 来源待考（G4 美术阶段补查） | 2026-07-20（随插件引入） |
| Ticketing.ttf 字体 | 来源待考（插件内未注明作者/许可证，G4 美术阶段补查） | 随插件自带，无独立 URL | 来源待考（G4 美术阶段补查） | 2026-07-20（随插件引入） |

---

## 二、音频资产（godot/assets/audio/）

> 一手清单见 `godot/assets/audio/LICENSES.md`（含每个文件的原始条目名与直链）。
> Mixkit 条目适用 **Mixkit Free License**（https://mixkit.co/license/#sfxFree）：可免费用于商业与非商业项目，无需署名，可修改。

| 名称 | 作者 | URL | 许可证 | 日期 |
|------|------|-----|--------|------|
| rifle.mp3（步枪单发） | Mixkit（页面未单独署名） | https://mixkit.co/free-sound-effects/download/1662/ | Mixkit Free License | 2026-07-14 |
| rocket.mp3（火箭筒发射） | Mixkit（页面未单独署名） | https://mixkit.co/free-sound-effects/download/1714/ | Mixkit Free License | 2026-07-14 |
| explosion.mp3（爆炸） | Mixkit（页面未单独署名） | https://mixkit.co/free-sound-effects/download/1694/ | Mixkit Free License | 2026-07-14 |
| reload.mp3（换弹/拉栓） | Mixkit（页面未单独署名） | https://mixkit.co/free-sound-effects/download/1666/ | Mixkit Free License | 2026-07-14 |
| hitmark.mp3（命中提示） | Mixkit（页面未单独署名） | https://mixkit.co/free-sound-effects/download/2073/ | Mixkit Free License | 2026-07-14 |
| footstep.mp3（脚步，可循环） | Mixkit（页面未单独署名） | https://mixkit.co/free-sound-effects/download/535/ | Mixkit Free License | 2026-07-14 |
| helicopter.mp3（直升机旋翼，可循环） | Mixkit（页面未单独署名） | https://mixkit.co/free-sound-effects/download/2704/ | Mixkit Free License | 2026-07-14 |
| nightvision.mp3（夜视仪开关/电流声） | Mixkit（页面未单独署名） | https://mixkit.co/free-sound-effects/download/2602/ | Mixkit Free License | 2026-07-14 |
| medkit.mp3（治疗/包扎） | Mixkit（页面未单独署名） | https://mixkit.co/free-sound-effects/download/3102/ | Mixkit Free License | 2026-07-14 |
| ui_click.mp3（UI 点击） | Mixkit（页面未单独署名） | https://mixkit.co/free-sound-effects/download/2568/ | Mixkit Free License | 2026-07-14 |
| ambient.wav（战场环境音，可循环 34s） | 本项目程序合成占位（Node 脚本生成，非第三方素材） | 无（本地合成） | 项目自有资产（等同 CC0） | 2026-07-14 |

---

## 三、机主原创资产（非第三方，登记以备溯源）

| 名称 | 作者 | 来源 | 许可证 | 日期 |
|---|---|---|---|---|
| edaa_emblem.png（EDAA 徽记，臂章/开头画面/UI 唯一图样基准，见 `desktop-port/godot-spike/07-snuffers-art-design.md` §3.1） | 机主（EDAA 原创设定体系，源文件 `E:\EDAA\EDAA徽记.png`） | 本地原创 | 项目自有（机主版权所有） | 2026-08-19 |

---

## 四、AI 生成资产（Kimi image_generation 插件，项目自有）

> 由本 Agent 经 Kimi image_generation 插件生成（机主提供豆包参考图定风格），
> 无第三方版权负担，等同项目自有资产；入库前已裁除生成水印条。

| 名称 | 用途 | 生成工具 | 许可证 | 日期 |
|---|---|---|---|---|
| `assets/textures/skyline/pano_a.png` | CBD 夜景全景幕布卡 A（3072×976） | Kimi image_generation（豆包参考图风格引导） | 项目自有（AI 生成） | 2026-09-27 |
| `assets/textures/skyline/pano_b.png` | CBD 夜景全景幕布卡 B（3072×976） | 同上 | 项目自有（AI 生成） | 2026-09-27 |
| `assets/textures/skyline/facade_office.png` | 玻璃幕墙办公楼立面贴图（1024×1488） | 同上 | 项目自有（AI 生成） | 2026-09-27 |
| `assets/textures/skyline/facade_residential.png` | 住宅塔楼立面贴图（1024×1488） | 同上 | 项目自有（AI 生成） | 2026-09-27 |
| `assets/textures/skyline/facade_neon.png` | 霓虹媒体立面塔楼贴图（1024×1488，无文字版） | 同上 | 项目自有（AI 生成） | 2026-09-27 |

---

## 五、第三方 3D 模型资产（godot/assets/models/）

| 名称 | 作者 | URL | 许可证 | 日期 |
|------|------|-----|--------|------|
| prop_basketball_hoop.glb（「Basket ball and hoop」，巷弄篮球场道具） | Armory_3D（Poly Pizza 分发） | https://poly.pizza/m/i3LLacyQP4 | CC0 | 2026-09-27 |
| prop_bicycle.glb（「Bicycle」，巷弄靠墙自行车道具） | Poly by Google（Poly Pizza 分发） | https://poly.pizza/m/0Lk0xuhWE3b | CC-BY（**需游戏内署名**） | 2026-09-27 |

---

## 六、待办与合规提示

1. **「来源待考」条目**：凡标注「来源待考（G4 美术阶段补查）」者，均为本地文件内无法查证作者/许可证，已如实标注、未作编造；G4 美术阶段须逐项补查或替换为许可证明确的资产。
2. **CC-BY 署名义务**：Ammo Canister（Stephen Yoshimura, CC-BY）与 Bicycle（Poly by Google, CC-BY）若最终进入包体，须在游戏内（结算/关于界面）署名。
3. **原始文件入库红线**：jeh3no 插件内自带 `Weapons.fbx`、`low_poly_rpg-7/scene.gltf` 等原始模型文件，与约束 #7「Sketchfab 等原始文件禁止提交进 git 仓库」存在潜在冲突；当前 spike 阶段业务场景不引用这些资源，是否剔除或 .gitignore 排除由蜂后裁决。
4. **占位资产替换**：`ambient.wav` 为程序合成占位，夜视/昼夜相关音效与视觉素材按 W7 交接备忘录于 G4 后由 W5 替换正式资产，替换时同步更新本台账。
