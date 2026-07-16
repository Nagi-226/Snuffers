# 音效资源授权清单（LICENSES）

项目：废墟突围（Ruins-Breakout）· dev_win 分支
整理日期：2026-07-14（UTC+8）
整理人：音效资源猎手（子代理）

---

## 许可证说明

- **Mixkit Free License**（https://mixkit.co/license/#sfxFree）：Mixkit 音效可免费用于商业与非商业项目，无需署名，可修改。本次下载的 12 个文件均来自 Mixkit 官方音效库，直接下载、无需登录、无付费项。
- **程序合成占位**：`ambient.wav` 由本项目 Node 脚本程序化合成（棕噪声风声 + 随机远处枪声爆点 + 低频爆炸隆隆声），非第三方素材，可视为项目自有资产（等同于 CC0），无任何授权限制。

---

## 文件清单

| 文件名 | 用途 | 来源平台 | 原始条目 | 作者 | 原始 URL | 许可证 | 下载日期 |
|---|---|---|---|---|---|---|---|
| rifle.mp3 | 步枪单发 | Mixkit | Game gun shot | Mixkit（页面未单独署名） | https://mixkit.co/free-sound-effects/download/1662/ （直链 https://assets.mixkit.co/active_storage/sfx/1662/1662.mp3 ） | Mixkit Free License | 2026-07-14 |
| rocket.mp3 | 火箭筒发射 | Mixkit | Fast rocket whoosh | Mixkit（页面未单独署名） | https://mixkit.co/free-sound-effects/download/1714/ （直链 https://assets.mixkit.co/active_storage/sfx/1714/1714-preview.mp3 ） | Mixkit Free License | 2026-07-14 |
| explosion.mp3 | 爆炸 | Mixkit | Short explosion | Mixkit（页面未单独署名） | https://mixkit.co/free-sound-effects/download/1694/ （直链 https://assets.mixkit.co/active_storage/sfx/1694/1694-preview.mp3 ） | Mixkit Free License | 2026-07-14 |
| reload.mp3 | 换弹/拉栓 | Mixkit | Shotgun long pump | Mixkit（页面未单独署名） | https://mixkit.co/free-sound-effects/download/1666/ （直链 https://assets.mixkit.co/active_storage/sfx/1666/1666-preview.mp3 ） | Mixkit Free License | 2026-07-14 |
| hitmark.mp3 | 命中提示 | Mixkit | Game ball tap | Mixkit（页面未单独署名） | https://mixkit.co/free-sound-effects/download/2073/ （直链 https://assets.mixkit.co/active_storage/sfx/2073/2073-preview.mp3 ） | Mixkit Free License | 2026-07-14 |
| enemy_death.mp3 | 敌人倒地 | Mixkit | Man in pain | Mixkit（页面未单独署名） | https://mixkit.co/free-sound-effects/download/2197/ （直链 https://assets.mixkit.co/active_storage/sfx/2197/2197-preview.mp3 ） | Mixkit Free License | 2026-07-14 |
| player_hurt.mp3 | 玩家受伤 | Mixkit | Ow exclamation of pain | Mixkit（页面未单独署名） | https://mixkit.co/free-sound-effects/download/2204/ （直链 https://assets.mixkit.co/active_storage/sfx/2204/2204-preview.mp3 ） | Mixkit Free License | 2026-07-14 |
| footstep.mp3 | 脚步（可循环） | Mixkit | Crunchy footsteps loop | Mixkit（页面未单独署名） | https://mixkit.co/free-sound-effects/download/535/ （直链 https://assets.mixkit.co/active_storage/sfx/535/535-preview.mp3 ） | Mixkit Free License | 2026-07-14 |
| helicopter.mp3 | 直升机旋翼（可循环） | Mixkit | Helicopter propellers in the sky | Mixkit（页面未单独署名） | https://mixkit.co/free-sound-effects/download/2704/ （直链 https://assets.mixkit.co/active_storage/sfx/2704/2704-preview.mp3 ） | Mixkit Free License | 2026-07-14 |
| nightvision.mp3 | 夜视仪开关/电流声 | Mixkit | Electronics power up | Mixkit（页面未单独署名） | https://mixkit.co/free-sound-effects/download/2602/ （直链 https://assets.mixkit.co/active_storage/sfx/2602/2602-preview.mp3 ） | Mixkit Free License | 2026-07-14 |
| medkit.mp3 | 治疗/包扎 | Mixkit | Duct tape bandage | Mixkit（页面未单独署名） | https://mixkit.co/free-sound-effects/download/3102/ （直链 https://assets.mixkit.co/active_storage/sfx/3102/3102-preview.mp3 ） | Mixkit Free License | 2026-07-14 |
| ui_click.mp3 | UI 点击 | Mixkit | Cool interface click tone | Mixkit（页面未单独署名） | https://mixkit.co/free-sound-effects/download/2568/ （直链 https://assets.mixkit.co/active_storage/sfx/2568/2568-preview.mp3 ） | Mixkit Free License | 2026-07-14 |
| ambient.wav | 战场环境音（风声+远处枪声，可循环 34s） | **程序合成占位** | Node 脚本合成（棕噪声风声 LFO + 随机远处枪声/爆炸，22050Hz 单声道 16bit WAV，首尾各 1s 淡化便于循环） | 本项目自生成 | 无（本地合成） | 项目自有资产（等同 CC0） | 2026-07-14 |

---

## 备注

1. Mixkit 各条目官方下载文件多为 WAV；为保持任务规定的 `.mp3` 文件名与 MP3 内容一致，本次统一采用其官方 `-preview.mp3` 版本（同一音效的完整 MP3 编码，288kbps 立体声），仅 `rifle.mp3` 为官方原始 MP3 下载文件（ID3，448kbps）。
2. `ambient.wav` 为 RIFF/WAV 数据（任务允许的合成占位方案）。原曾以 `.mp3` 为文件名入库，因 Godot MP3 导入器按扩展名校验拒绝 WAV 数据，经蜂后裁决（D1，2026-07-16）重命名为 `.wav`，加载端先找 `.mp3` 再找 `.wav` 以兼容。
3. 所有文件已验证：文件头为 ID3 或 MP3 帧同步字（ff fb），大小均 > 5KB；`helicopter.mp3`（约 561KB）与 `ambient.wav`（约 1.4MB）满足 > 100KB 要求。
4. 未使用任何需登录、付费或仅限个人使用的资源。Pixabay（搜索页需 JS 渲染无法直链验证）与 OpenGameArt（检索结果以音乐为主、无合适战场环境音直链）本轮未采用。
