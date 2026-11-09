# ATTRIBUTION.md — assets/textures（PBR 材质贴图）

> 所有材质组来自 ambientCG（https://ambientcg.com），**CC0 1.0 公有领域**（无署名义务，
> 依 AGENTS.md 资产卫生规则 #7 仍登记台账）。下载日期 2026-10-25；入库仅保留
> Color/NormalGL/Roughness 三图（1K-JPG，snake_case 重命名），原始 zip 存
> `godot/raw_assets/pbr_sets/`（gitignore 排除不入库）。

| 材质组 | 用途 | 源 URL | 许可证 | 入库路径 |
|---|---|---|---|---|
| Plaster004 | 建筑立面抹灰 A（plaster_cream） | https://ambientcg.com/get?file=Plaster004_1K-JPG.zip | CC0 | `pbr/plaster004/` |
| Plaster006 | 建筑立面抹灰 B（plaster_sand/pink） | https://ambientcg.com/get?file=Plaster006_1K-JPG.zip | CC0 | `pbr/plaster006/` |
| PaintedPlaster002 | 室内漆面抹灰（plaster_white） | https://ambientcg.com/get?file=PaintedPlaster002_1K-JPG.zip | CC0 | `pbr/paintedplaster002/` |
| Bricks003 | 砖墙（brick） | https://ambientcg.com/get?file=Bricks003_1K-JPG.zip | CC0 | `pbr/bricks003/` |
| WoodFloor002 | 室内木地板（备用，未接线） | https://ambientcg.com/get?file=WoodFloor002_1K-JPG.zip | CC0 | `pbr/woodfloor002/` |
| Concrete034 | 混凝土（备用，未接线） | https://ambientcg.com/get?file=Concrete034_1K-JPG.zip | CC0 | `pbr/concrete034/` |

**生成管线**: `godot/tools/gen_pbr_materials.gd`（三平面世界空间 StandardMaterial3D .tres，
程序化几何零 UV 依赖；尺度分档沿 P1 纪律：建筑面 2.5m/砖 1.0m）。

## 第一关材质样板（2026-11-09）

由 `StreetQualitySample` 使用：局部样板已由机主验收，2026-11-09追加授权
应用于第一关完整街区的同类墙面、道路与金属门。以下素材来自
Poly Haven，CC0 1.0（https://polyhaven.com/license）；2K JPG，保留 Diffuse /
Normal OpenGL / Roughness 三图。通过公开 files API 获取下载地址，下载后逐图核对
清单 MD5；原下载清单保留在本地 `.kimi-tmp/street_sample/`。

| 名称 | 作者 | 源 URL | 许可证 | 日期 | 入库路径 |
|---|---|---|---|---|---|
| Asphalt 02 | Rob Tuytel | https://polyhaven.com/a/asphalt_02 | CC0 1.0 | 2026-11-09 | `street_sample/asphalt_{color,normal,rough}.jpg` |
| Plastered Wall 02 | Charlotte Baglioni | https://polyhaven.com/a/plastered_wall_02 | CC0 1.0 | 2026-11-09 | `street_sample/plaster_{color,normal,rough}.jpg` |
| Green Metal Rust | Rob Tuytel | https://polyhaven.com/a/green_metal_rust | CC0 1.0 | 2026-11-09 | `street_sample/metal_{color,normal,rough}.jpg` |

扫描宽度分别为 3m、2.23m、1m，三平面投影按米周期倒数设置 UV scale。
金属门展示漆面与氧化锈层，使用非金属表面反射；不将整张漆锈图设为 metallic=1。
路灯为本项目用 Godot 基础几何构建的原创模型（2026-11-09）。
