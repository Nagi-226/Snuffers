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
