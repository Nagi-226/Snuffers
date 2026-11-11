# 音效资源授权清单（LICENSES）

项目：熄烛者（Snuffers）· dev_win 分支
整理日期：2026-07-14（UTC+8）
整理人：音效资源猎手（子代理）

---

## 许可证说明

- **Mixkit Free License**（https://mixkit.co/license/#sfxFree）：Mixkit 音效可免费用于商业与非商业项目，无需署名，可修改。本次下载的 12 个文件均来自 Mixkit 官方音效库，直接下载、无需登录、无付费项。**2026-08-20 机主指令移除 2 个人声呻吟条目（enemy_death「Man in pain」/ player_hurt「Ow exclamation of pain」，违和感太强），现库内 Mixkit 文件 10 个。**2026-10-19 新增 pistol.mp3（Short laser gun shot，机主立项：EM-57P 手枪与步枪不共用枪声素材），现库内 Mixkit 文件 11 个。**
- **程序合成占位**：`ambient.wav` 由本项目 Node 脚本程序化合成（棕噪声风声 + 随机远处枪声爆点 + 低频爆炸隆隆声），非第三方素材，可视为项目自有资产（等同于 CC0），无任何授权限制。

---

## 文件清单

| 文件名 | 用途 | 来源平台 | 原始条目 | 作者 | 原始 URL | 许可证 | 下载日期 |
|---|---|---|---|---|---|---|---|
| rifle.mp3 | 步枪单发 | Mixkit | Game gun shot | Mixkit（页面未单独署名） | https://mixkit.co/free-sound-effects/download/1662/ （直链 https://assets.mixkit.co/active_storage/sfx/1662/1662.mp3 ） | Mixkit Free License | 2026-07-14 |
| pistol.mp3 | 手枪单发（EM-57P「掣」，电磁短促激光枪感，与步枪音源区分） | Mixkit | Short laser gun shot | Mixkit（页面未单独署名） | https://mixkit.co/free-sound-effects/download/1670/ （直链 https://assets.mixkit.co/active_storage/sfx/1670/1670-preview.mp3 ） | Mixkit Free License | 2026-10-19 |
| rocket.mp3 | 火箭筒发射 | Mixkit | Fast rocket whoosh | Mixkit（页面未单独署名） | https://mixkit.co/free-sound-effects/download/1714/ （直链 https://assets.mixkit.co/active_storage/sfx/1714/1714-preview.mp3 ） | Mixkit Free License | 2026-07-14 |
| explosion.mp3 | 爆炸 | Mixkit | Short explosion | Mixkit（页面未单独署名） | https://mixkit.co/free-sound-effects/download/1694/ （直链 https://assets.mixkit.co/active_storage/sfx/1694/1694-preview.mp3 ） | Mixkit Free License | 2026-07-14 |
| reload.mp3 | 换弹/拉栓 | Mixkit | Shotgun long pump | Mixkit（页面未单独署名） | https://mixkit.co/free-sound-effects/download/1666/ （直链 https://assets.mixkit.co/active_storage/sfx/1666/1666-preview.mp3 ） | Mixkit Free License | 2026-07-14 |
| hitmark.mp3 | 命中提示 | Mixkit | Game ball tap | Mixkit（页面未单独署名） | https://mixkit.co/free-sound-effects/download/2073/ （直链 https://assets.mixkit.co/active_storage/sfx/2073/2073-preview.mp3 ） | Mixkit Free License | 2026-07-14 |
| footstep.mp3 | 脚步（可循环） | Mixkit | Crunchy footsteps loop | Mixkit（页面未单独署名） | https://mixkit.co/free-sound-effects/download/535/ （直链 https://assets.mixkit.co/active_storage/sfx/535/535-preview.mp3 ） | Mixkit Free License | 2026-07-14 |
| helicopter.mp3 | 直升机旋翼（可循环） | Mixkit | Helicopter propellers in the sky | Mixkit（页面未单独署名） | https://mixkit.co/free-sound-effects/download/2704/ （直链 https://assets.mixkit.co/active_storage/sfx/2704/2704-preview.mp3 ） | Mixkit Free License | 2026-07-14 |
| nightvision.mp3 | 夜视仪开关/电流声 | Mixkit | Electronics power up | Mixkit（页面未单独署名） | https://mixkit.co/free-sound-effects/download/2602/ （直链 https://assets.mixkit.co/active_storage/sfx/2602/2602-preview.mp3 ） | Mixkit Free License | 2026-07-14 |
| medkit.mp3 | 治疗/包扎 | Mixkit | Duct tape bandage | Mixkit（页面未单独署名） | https://mixkit.co/free-sound-effects/download/3102/ （直链 https://assets.mixkit.co/active_storage/sfx/3102/3102-preview.mp3 ） | Mixkit Free License | 2026-07-14 |
| ui_click.mp3 | UI 点击 | Mixkit | Cool interface click tone | Mixkit（页面未单独署名） | https://mixkit.co/free-sound-effects/download/2568/ （直链 https://assets.mixkit.co/active_storage/sfx/2568/2568-preview.mp3 ） | Mixkit Free License | 2026-07-14 |
| ambient.wav | 战场环境音（风声+远处枪声，可循环 34s） | **程序合成占位** | Node 脚本合成（棕噪声风声 LFO + 随机远处枪声/爆炸，22050Hz 单声道 16bit WAV，首尾各 1s 淡化便于循环） | 本项目自生成 | 无（本地合成） | 项目自有资产（等同 CC0） | 2026-07-14 |
| spore.mp3 | 寄生体孢子团投掷（黏性有机喷吐质感，2026-10-21 机主裁决：与枪声彻底区分，参考《半衰期》牛乌贼喷酸） | **AI 生成** | Kimi audio_generation 插件 sound-effects 流程（英文描述生成，1.5s） | 本项目自生成 | 无（AI 生成） | 项目自有资产（等同 CC0） | 2026-10-21 |
| spore.mp3（2026-10-25 重渲染） | 戈诺姆式厚重孢子投掷（降调 0.74× 增重+响度规整 I=-20LUFS，时长 1.5→2.0s；机主 2026-10-25 指令：原音效又快又响与动作不搭，参考《半衰期：针锋相对》戈诺姆远程孢子；因 Valve 版权不入库，以自有 AI 生成源改制） | **AI 生成后本地改制** | ffmpeg `asetrate=44100*0.74,aresample=44100,loudnorm=I=-20:TP=-3:LRA=7`，源为 2026-10-21 自生成文件（git 历史可溯） | 本项目自生成 | 无（AI 生成） | 项目自有资产（等同 CC0） | 2026-10-25 |

| nano_armor.wav | 装甲模式启动（机械装甲＋轻护盾能量底音，替换先前 3.2s 机器启动候选） | Freesound | Robot / Mech movement；EnergyShield.mp3（仅 22% 音量底音） | Breviceps；Beussa | https://freesound.org/people/Breviceps/sounds/505670/ （预览 https://cdn.freesound.org/previews/505/505670_9159316-hq.mp3 ）；https://freesound.org/people/Beussa/sounds/659967/ | 均 CC0（可商用、可修改） | 2026-11-07（混合为 1.2s，淡入淡出、-18 LUFS、44.1kHz 立体声） |
| nano_stealth.wav | 隐形模式启动（短促力场展开，替换原 0.85s 合成占位；与夜视仪完全独立） | Freesound | Landing Forcefield | unfa | https://freesound.org/people/unfa/sounds/584173/ （官方预览 https://cdn.freesound.org/previews/584/584173_1038806-hq.mp3 ） | CC0（可商用、可修改） | 2026-11-07（淡入淡出、-18 LUFS 响度统一、44.1kHz 立体声） |
| railgun.wav | EM-127G 重型反器材高斯步枪重炮击发（独立音源，突出冲击力） | Freesound | Railgun - Extremely LOUD Cannon | qubodup | https://freesound.org/people/qubodup/sounds/162260/ （官方预览 https://cdn.freesound.org/previews/162/162260_71257-hq.mp3 ） | CC0（可商用、可修改） | 2026-11-07（截取 0–2.8s、淡入淡出、-16 LUFS、44.1kHz 立体声） |
| railgun_charged.wav | EM-127G 充能击发（在普通重炮音上叠加短促电磁放电瞬态） | Freesound 衍生＋本项目合成 | Railgun - Extremely LOUD Cannon；程序合成电磁瞬态 | qubodup；本项目 | https://freesound.org/people/qubodup/sounds/162260/ | CC0／项目自有合成部分 | 2026-11-07（2.8s、淡入淡出、-15 LUFS、44.1kHz 立体声 PCM） |
| g17.wav | Glock 17 Gen5 单发；原始录音为 Glock 17 真枪射击，不是 Gen5 专属录音 | Freesound | glock17_02.wav | gezortenplotz | https://freesound.org/people/gezortenplotz/sounds/34982/ （官方 HQ 预览 https://cdn.freesound.org/previews/34/34982_11536-hq.mp3 ） | [CC-BY 3.0](https://creativecommons.org/licenses/by/3.0/)；可商用、可修改，须署名 | 2026-11-11（单发裁剪、低切、淡变、响度处理；0.75s、44.1kHz 单声道 PCM16） |
| mpx.wav | SIG MPX 开火近似；源为 MP5A3 9mm 真枪空包弹录音，不是 MPX 或实弹的原录 | Freesound | MP5 submachine gun down the street.aif | Franki-01234 | https://freesound.org/people/Franki-01234/sounds/201671/ （官方 HQ 预览 https://cdn.freesound.org/previews/201/201671_3749344-hq.mp3 ） | [CC0](https://creativecommons.org/publicdomain/zero/1.0/)；可商用、可修改 | 2026-11-11（取连发最后一发及尾声，低切、淡变、响度处理；0.60s、44.1kHz 单声道 PCM16） |

### 9×19 枪声来源与衍生记录（2026-11-11）

- G17 页面明确说明为作者在户外靶场录制的 Glock 17 9mm 发射声；源发布日期 2007-05-17。没有将源描述升级为 Gen5 型号录音。MP5 页面明确说明作者为自己的独立电影录制真枪空包弹，枪型为 Heckler & Koch MP5A3—9mm；源发布日期 2013-09-28。
- 本轮未找到开放许可的确切 MPX 真枪开火录音：Freesound 的 `MPX gun` / `MPX firing` 无结果，精确网络查询只找到商业库。MP5A3 近似保留火药枪发射声及街道尾响，与 G17 使用两个独立音源；不复用 `pistol.mp3` 的电磁激光声，不采用 airsoft、NC 素材或出处不明的游戏拆包。
- 本次下载为公开、可依法改作的官方 HQ MP3 预览；Freesound 原 WAV/AIFF 下载需登录，本轮未取得原无损文件。源 MP3 保留在本地未入库目录 `.kimi-tmp/nov11_g17_mpx/audio_sources/`；入库 WAV 是解码处理输出，不声称恢复了无损源质量。
- G17 处理：从解码后的源时间轴裁 `7.215–7.965s`，保留一发起音及回响；MPX 近似从 MP5 源裁 `1.709–2.309s`，只保留连发最后一发，不将整段连发声当单发重复触发。两者使用 ffmpeg 已安装工具，`highpass=f=70`、1ms 淡入、末尾 180/200ms 淡出、`loudnorm=I=-18:TP=-3:LRA=7`，输出 44.1kHz 单声道 PCM16 WAV。以上为离线音频编辑步骤，不新增运行时依赖。
- G17 官方 HQ 源 SHA256：`32828f632b97131f5b4236fe09b372f5fe789a8d817c50eddd7a480af5461c62`；衍生 `g17.wav` SHA256：`f2bcca2fe02855bed10cf9b75cdc4c7485a2107d381e8b34c8c757e92a70d59c`。
- MP5 官方 HQ 源 SHA256：`66f26be8d770b477e620f5fc6c3e56cfd0d5728d831b68425d1bea133c8893db`；衍生 `mpx.wav` SHA256：`6097c20ddf7870b46791b4474d25da8390df8dccff3cc08d25d123589e327ed0`。
- 游戏内标题“资产署名”列出 G17 作者 gezortenplotz、来源、CC-BY 3.0 与本项目剪辑处理；MP5A3 近似同时列作者 Franki-01234、CC0 和原录边界。

---

## 备注

1. Mixkit 各条目官方下载文件多为 WAV；为保持任务规定的 `.mp3` 文件名与 MP3 内容一致，本次统一采用其官方 `-preview.mp3` 版本（同一音效的完整 MP3 编码，288kbps 立体声），仅 `rifle.mp3` 为官方原始 MP3 下载文件（ID3，448kbps）。
2. `ambient.wav` 为 RIFF/WAV 数据（任务允许的合成占位方案）。原曾以 `.mp3` 为文件名入库，因 Godot MP3 导入器按扩展名校验拒绝 WAV 数据，经蜂后裁决（D1，2026-07-16）重命名为 `.wav`，加载端先找 `.mp3` 再找 `.wav` 以兼容。
3. 所有文件已验证：文件头为 ID3 或 MP3 帧同步字（ff fb），大小均 > 5KB；`helicopter.mp3`（约 561KB）与 `ambient.wav`（约 1.4MB）满足 > 100KB 要求。
4. 未使用任何需登录、付费或仅限个人使用的资源。Pixabay（搜索页需 JS 渲染无法直链验证）与 OpenGameArt（检索结果以音乐为主、无合适战场环境音直链）本轮未采用。
