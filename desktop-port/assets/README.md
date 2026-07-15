# Godot 重制版 — 美术资产策略总览

> 三份专项调研：`01-characters-animation.md`、`02-environment.md`、`03-weapons-vehicles-vfx.md`
> 调研日期：2026-07-15（本机中国大陆网络实测）

## 结论：CC0 低模生态可覆盖约 90% 资产需求，零采购预算

### 首选资产组合（全部免费可商用）

| 需求 | 首选 | 许可证 | 获取方式 |
|------|------|--------|----------|
| 角色+动画 | Quaternius UAL2 + Universal Base Characters（同骨架零重定向，130+ 动画） | CC0 | quaternius.com 直连 ✅ |
| 武器 | Quaternius Ultimate Guns Pack（25 把低模枪） | CC0 | quaternius.com ✅ |
| 环境主体 | Quaternius Downtown City MegaKit（300+ 城市件） | CC0 | quaternius.com ✅ |
| 废墟氛围 | Kenney Graveyard Kit + KayKit Dungeon Remastered | CC0 | kenney.nl ✅ / GitHub ✅ |
| 地形杂物 | Kenney Nature Kit | CC0 | kenney.nl ✅ |
| 道具（地雷/药包） | Quaternius Toon Shooter Kit + First Aid Kit | CC0 | quaternius.com ✅ |
| 特效贴图/UI | Kenney Particle/Smoke/Crosshair/UI Sci-fi 四件套 | CC0 | kenney.nl ✅ |
| 武器系统脚手架 | Jeh3no/Godot-simple-FPS-weapon-system（连代码+特效结构） | MIT | GitHub ✅ |
| 直升机 | KumaSousa Low Poly Helicopter（旋翼分离） | CC0 | ⚠️ itch.io 被墙，需镜像/代理 |
| 补充动画 | Mixamo（FBX→FBX2glTF/Blender 转 glTF） | 可商用禁再分发 | mixamo.com，⚠️ 原始文件禁入仓库 |

### 中国大陆可达性实测（2026-07-15）

- ✅ 可达：quaternius.com、kenney.nl、github.com、opengameart.org、mixamo.com
- ❌ 被墙：itch.io、poly.pizza、godotengine.org（**编辑器内 AssetLib 面板连带不可用**，需离线下载或 GitHub 镜像）
- 绕行方案：KayKit → GitHub 组织 `KayKit-Game-Assets`；AssetLib 条目 → GitHub 直链

### 三大缺口与解法

1. **现代军事杂物 CC0 空缺**（沙袋/铁丝网/碉堡/油桶）→ 灰盒自制 5–8 件（BoxMesh 拼装，约 1 人日，与低模风格兼容）
2. **第一人称手部/持枪动画无现成资产** → Mixamo 上身动画裁切，或 Jeh3no 系统的程序化摆动/后坐力
3. **三家色板风格不一**（Kenney 饱和 / Quaternius 写实灰 / KayKit 卡通）→ 统一降饱和 + 冷灰蓝重染（每包 1 张小色板，小时级工作量），夜战月光下验收

### 法律卫生（强制）

- 每个入库资产登记到 `ATTRIBUTION.md`（名称/作者/URL/许可证/日期），CC-BY 类在游戏内署名
- Mixamo、PolyPack（FAL 许可）原始文件**禁止提交进 git 仓库**（尤其公开仓库），只能烘焙进游戏包体，.gitignore 排除
- Sketchfab 单品逐件核授权（实测混入 CC-BY-NC-ND 不可用项）
- 音效授权台账已有先例：`audio/LICENSES.md`

### 特效策略

GPUParticles3D 自制为主（Godot 商店 3D 战斗特效成品极少）+ Kenney 贴图 + 借用 Jeh3no 特效场景结构。
