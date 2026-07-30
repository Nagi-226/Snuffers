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
| enemy_death.mp3（敌人倒地） | Mixkit（页面未单独署名） | https://mixkit.co/free-sound-effects/download/2197/ | Mixkit Free License | 2026-07-14 |
| player_hurt.mp3（玩家受伤） | Mixkit（页面未单独署名） | https://mixkit.co/free-sound-effects/download/2204/ | Mixkit Free License | 2026-07-14 |
| footstep.mp3（脚步，可循环） | Mixkit（页面未单独署名） | https://mixkit.co/free-sound-effects/download/535/ | Mixkit Free License | 2026-07-14 |
| helicopter.mp3（直升机旋翼，可循环） | Mixkit（页面未单独署名） | https://mixkit.co/free-sound-effects/download/2704/ | Mixkit Free License | 2026-07-14 |
| nightvision.mp3（夜视仪开关/电流声） | Mixkit（页面未单独署名） | https://mixkit.co/free-sound-effects/download/2602/ | Mixkit Free License | 2026-07-14 |
| medkit.mp3（治疗/包扎） | Mixkit（页面未单独署名） | https://mixkit.co/free-sound-effects/download/3102/ | Mixkit Free License | 2026-07-14 |
| ui_click.mp3（UI 点击） | Mixkit（页面未单独署名） | https://mixkit.co/free-sound-effects/download/2568/ | Mixkit Free License | 2026-07-14 |
| ambient.wav（战场环境音，可循环 34s） | 本项目程序合成占位（Node 脚本生成，非第三方素材） | 无（本地合成） | 项目自有资产（等同 CC0） | 2026-07-14 |

---

## 三、待办与合规提示

1. **「来源待考」条目**：凡标注「来源待考（G4 美术阶段补查）」者，均为本地文件内无法查证作者/许可证，已如实标注、未作编造；G4 美术阶段须逐项补查或替换为许可证明确的资产。
2. **CC-BY 署名义务**：Ammo Canister（Stephen Yoshimura, CC-BY）若最终进入包体，须在游戏内（结算/关于界面）署名。
3. **原始文件入库红线**：jeh3no 插件内自带 `Weapons.fbx`、`low_poly_rpg-7/scene.gltf` 等原始模型文件，与约束 #7「Sketchfab 等原始文件禁止提交进 git 仓库」存在潜在冲突；当前 spike 阶段业务场景不引用这些资源，是否剔除或 .gitignore 排除由蜂后裁决。
4. **占位资产替换**：`ambient.wav` 为程序合成占位，夜视/昼夜相关音效与视觉素材按 W7 交接备忘录于 G4 后由 W5 替换正式资产，替换时同步更新本台账。
