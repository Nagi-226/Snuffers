class_name StreetLayoutTest
extends RefCounted

## P0 试验街布局数据表 — 借鉴 Claude-of-Duty layout.js 的声明式范式（见文档10 §1-P0）
## 整张街区 = 本表；builder（street_builder.gd）只解释数据，不硬编码任何尺寸。
## 坐标系: 主街沿 Z 轴（-Z 为远/北），X 为横向。单位: 米。
## 地图编号（文档12 地图序列规划）: 本图 = c1m1_oldtown_south（城中村南段）

const STREET := {
	"half_width": 4.5,   # 沥青路面半宽
	"kerb": 6.5,         # 建筑线（人行道外缘）
	"walk_h": 0.145,     # 人行道抬高
	"z_min": -160.0,     # 沥青向北延伸进夜雾深处（EDAA 路障后 64m 视觉延续，雾遮蔽中断处）
	"z_max": 30.0,
	"wire_z_min": -92.0, # 跨街电线只拉到 EDAA 路障附近（路障后无人区不再拉线）
	"floor_h": 3.0,      # 层高
}

## 南端 T 字横街（2026-09-27 机主裁决：禁止房屋直接堵死马路；
## 主街 z_max 处转为东西向横街）
## 2026-09-27 二次裁决：横街两端同样改为 EDAA 力场幕墙 + 延伸式马路（四向统一），
## 沥青/人行道直达 x=±96 没入夜雾，力场位于 x=±38.5（夹道楼排间隙处）
const CROSS := {
	"z_min": 30.0,       # 横街沥青北缘（接主街断头处）
	"z_max": 36.5,       # 横街沥青南缘
	"x_min": -96.0,      # 沥青西延进夜雾深处
	"x_max": 96.0,       # 沥青东延进夜雾深处
	"walk_south_z": 38.5, # 南侧人行道南缘（建筑线）
	"walk_north_z": 28.5, # 北侧人行道北缘（x=±6.5 以外段）
}

## 主街南延段（2026-09-27 机主裁决：T 字路口不许被楼堵死——主街继续向南延伸，
## 与北端同款 EDAA 力场幕墙隔开，路面延伸进夜雾深处遮蔽中断处）
const SOUTH_EXT := {
	"z_min": 36.5,       # 接横街沥青南缘
	"z_max": 105.0,      # 南延 68.5m，雾能见度 60m 从路口算，末端全雾遮蔽
	"field_z": 68.0,     # 南端 EDAA 力场幕墙位（距路口 38m，清晰可读）
}

## 巷弄尽头围挡样式（机主裁决：巷子不得直通虚空——铁栅栏挡人，
## 外推 wall_depth 处红砖长墙断视线；墙厚 0.25m，比楼体薄；
## wall_extend 为墙体超出栏段两端的长度，防止掠射角视线从墙端缝隙漏到虚空）
const BARRIER_STYLE := {
	"fence_h": 1.9,
	"wall_h": 3.0,       # 2026-09-27 二次裁决加高（原 2.6 遮不严）
	"wall_t": 0.25,
	"wall_depth": 6.0,
	"wall_extend": 3.0,
}

## 巷道/空地: rect=[x0, z0, x1, z1]，surface 为地面材质键
## RE3 重制版式巷弄生活区：巷口窄道 + 巷尾院落（篮球场/露天小酒馆）
const ALLEYS := [
	{"rect": [-20.0, -12.0, -6.5, -8.0], "surface": "paving"},    # 西侧巷道
	{"rect": [6.5, 2.0, 22.0, 8.0], "surface": "paving"},          # 东侧 flank 巷
	{"rect": [-22.0, 14.0, -6.5, 20.0], "surface": "paving"},      # 西侧院落
	# —— 北延段巷弄（2026-09-27 扩充）——
	{"rect": [-19.0, -32.0, -6.5, -27.0], "surface": "paving"},    # WA 西巷（通篮球场）
	{"rect": [-27.0, -66.0, -19.5, -52.0], "surface": "paving"},   # 篮球场院落（WB 巷尾）
	{"rect": [-19.5, -62.0, -6.5, -57.0], "surface": "paving"},    # WB 西巷（篮球场入口）
	{"rect": [6.5, -29.0, 19.0, -24.0], "surface": "paving"},      # EA 东巷（通小酒馆）
	{"rect": [19.0, -38.0, 27.0, -20.0], "surface": "paving"},     # 露天小酒馆院落
	{"rect": [6.5, -59.0, 19.0, -54.0], "surface": "paving"},      # EB 东巷
]

## 建筑: x/z 为体块中心，w=X 向宽，d=Z 向深，floors 层数，palette 为调色板键
## face 为立面朝向（"n"=朝北 -Z），缺省按旧规则（西排朝东/东排朝西/门楼朝南）
## 西排（x<0）与东排（x>0）贴建筑线布置；巷弄缺口处不留楼
const BUILDINGS := [
	{"id": "W1", "x": -11.5, "z": 23.0, "w": 10.0, "d": 12.0, "floors": 2, "palette": "plaster_cream"},
	{"id": "W2", "x": -11.5, "z": 10.0, "w": 10.0, "d": 14.0, "floors": 3, "palette": "plaster_sand"},
	{"id": "W3", "x": -11.5, "z": -2.0, "w": 10.0, "d": 10.0, "floors": 2, "palette": "plaster_white"},
	{"id": "W4", "x": -11.5, "z": -20.0, "w": 10.0, "d": 14.0, "floors": 3, "palette": "brick"},
	{"id": "E1", "x": 11.5, "z": 18.0, "w": 10.0, "d": 10.0, "floors": 2, "palette": "plaster_pink", "enterable": true},
	{"id": "E2", "x": 11.5, "z": -4.0, "w": 10.0, "d": 12.0, "floors": 3, "palette": "plaster_sand", "enterable": true},
	{"id": "E3", "x": 11.5, "z": -18.0, "w": 10.0, "d": 12.0, "floors": 2, "palette": "plaster_cream"},
	# —— 北延段楼群（2026-09-27 扩充：主街 z -27 → -87，巷弄缺口交错）——
	{"id": "W5", "x": -11.5, "z": -38.5, "w": 10.0, "d": 11.0, "floors": 3, "palette": "plaster_white"},
	{"id": "W6", "x": -11.5, "z": -51.0, "w": 10.0, "d": 12.0, "floors": 2, "palette": "brick"},
	{"id": "W7", "x": -11.5, "z": -69.0, "w": 10.0, "d": 12.0, "floors": 3, "palette": "plaster_sand"},
	{"id": "W8", "x": -11.5, "z": -82.0, "w": 10.0, "d": 10.0, "floors": 4, "palette": "plaster_cream"},
	{"id": "E4", "x": 11.5, "z": -36.0, "w": 10.0, "d": 12.0, "floors": 3, "palette": "plaster_sand"},
	{"id": "E5", "x": 11.5, "z": -49.0, "w": 10.0, "d": 10.0, "floors": 2, "palette": "plaster_cream"},
	{"id": "E6", "x": 11.5, "z": -66.0, "w": 10.0, "d": 12.0, "floors": 3, "palette": "brick"},
	{"id": "E7", "x": 11.5, "z": -79.0, "w": 10.0, "d": 12.0, "floors": 3, "palette": "plaster_white"},
	# —— 力场两翼贴楼 + 场后雾中楼排（2026-09-27 机主裁决：力场两侧贴紧建筑无缝隙；
	#     场后马路两旁楼排带门窗立面，延伸到雾气笼罩不可见处，z 约 -150 起全雾遮蔽）——
	{"id": "W9", "x": -11.5, "z": -91.5, "w": 10.0, "d": 11.0, "floors": 3, "palette": "plaster_sand"},
	{"id": "E8", "x": 11.5, "z": -91.5, "w": 10.0, "d": 11.0, "floors": 3, "palette": "plaster_cream"},
	{"id": "W10", "x": -11.5, "z": -104.0, "w": 10.0, "d": 12.0, "floors": 3, "palette": "plaster_pink"},
	{"id": "E9", "x": 11.5, "z": -104.0, "w": 10.0, "d": 12.0, "floors": 2, "palette": "plaster_white"},
	{"id": "W11", "x": -11.5, "z": -117.0, "w": 10.0, "d": 12.0, "floors": 4, "palette": "brick"},
	{"id": "E10", "x": 11.5, "z": -117.0, "w": 10.0, "d": 12.0, "floors": 3, "palette": "plaster_sand"},
	{"id": "W12", "x": -11.5, "z": -130.0, "w": 10.0, "d": 12.0, "floors": 3, "palette": "plaster_cream"},
	{"id": "E11", "x": 11.5, "z": -130.0, "w": 10.0, "d": 12.0, "floors": 4, "palette": "plaster_pink"},
	{"id": "W13", "x": -11.5, "z": -143.0, "w": 10.0, "d": 12.0, "floors": 2, "palette": "plaster_white"},
	{"id": "E12", "x": 11.5, "z": -143.0, "w": 10.0, "d": 12.0, "floors": 3, "palette": "brick"},
	# 横街南排（面朝北，临横街；T 字路口的临街面）
	# 2026-09-27 机主裁决：拆除堵主轴线的 S2，主街南延；S1/S3 拉宽贴走廊两翼
	{"id": "S1", "x": -16.25, "z": 43.5, "w": 19.5, "d": 10.0, "floors": 3, "palette": "plaster_sand", "face": "n"},
	{"id": "S3", "x": 16.25, "z": 43.5, "w": 19.5, "d": 10.0, "floors": 3, "palette": "plaster_pink", "face": "n"},
	# —— 南延走廊夹道楼排（贴建筑线 x=±6.5，SF_W2/SF_E2 跨力场位 z=68 无缝夹持）——
	{"id": "SF_W1", "x": -11.5, "z": 54.0, "w": 10.0, "d": 11.0, "floors": 2, "palette": "brick"},
	{"id": "SF_E1", "x": 11.5, "z": 54.0, "w": 10.0, "d": 11.0, "floors": 3, "palette": "plaster_cream"},
	{"id": "SF_W2", "x": -11.5, "z": 65.0, "w": 10.0, "d": 11.0, "floors": 3, "palette": "plaster_white"},
	{"id": "SF_E2", "x": 11.5, "z": 65.0, "w": 10.0, "d": 11.0, "floors": 2, "palette": "plaster_sand"},
	{"id": "SF_W3", "x": -11.5, "z": 76.5, "w": 10.0, "d": 12.0, "floors": 3, "palette": "plaster_cream"},
	{"id": "SF_E3", "x": 11.5, "z": 76.5, "w": 10.0, "d": 12.0, "floors": 4, "palette": "plaster_pink"},
	{"id": "SF_W4", "x": -11.5, "z": 88.5, "w": 10.0, "d": 12.0, "floors": 2, "palette": "plaster_sand"},
	{"id": "SF_E4", "x": 11.5, "z": 88.5, "w": 10.0, "d": 12.0, "floors": 3, "palette": "brick"},
	# —— 横街东西延伸段夹道楼排（四向力场裁决配套：北排面南 face=s，南排面北 face=n；
	#     力场 x=±38.5 落在 N1/N2、S1/S2 楼间隙处，间隙 1.5m 被幕墙填满）——
	{"id": "EW_N1", "x": 32.5, "z": 24.5, "w": 10.0, "d": 11.0, "floors": 3, "palette": "plaster_cream", "face": "s"},
	{"id": "EW_N2", "x": 44.5, "z": 24.5, "w": 10.0, "d": 11.0, "floors": 2, "palette": "plaster_sand", "face": "s"},
	{"id": "EW_N3", "x": 56.0, "z": 24.5, "w": 10.0, "d": 11.0, "floors": 4, "palette": "brick", "face": "s"},
	{"id": "EW_N4", "x": 67.5, "z": 24.5, "w": 10.0, "d": 11.0, "floors": 3, "palette": "plaster_white", "face": "s"},
	{"id": "EW_N5", "x": 79.0, "z": 24.5, "w": 10.0, "d": 11.0, "floors": 2, "palette": "plaster_pink", "face": "s"},
	{"id": "EW_S1", "x": 32.5, "z": 44.0, "w": 10.0, "d": 11.0, "floors": 2, "palette": "plaster_sand", "face": "n"},
	{"id": "EW_S2", "x": 44.5, "z": 44.0, "w": 10.0, "d": 11.0, "floors": 3, "palette": "plaster_white", "face": "n"},
	{"id": "EW_S3", "x": 56.0, "z": 44.0, "w": 10.0, "d": 11.0, "floors": 3, "palette": "plaster_cream", "face": "n"},
	{"id": "EW_S4", "x": 67.5, "z": 44.0, "w": 10.0, "d": 11.0, "floors": 2, "palette": "brick", "face": "n"},
	{"id": "EW_S5", "x": 79.0, "z": 44.0, "w": 10.0, "d": 11.0, "floors": 3, "palette": "plaster_sand", "face": "n"},
	{"id": "WW_N1", "x": -32.5, "z": 24.5, "w": 10.0, "d": 11.0, "floors": 2, "palette": "plaster_pink", "face": "s"},
	{"id": "WW_N2", "x": -44.5, "z": 24.5, "w": 10.0, "d": 11.0, "floors": 3, "palette": "plaster_white", "face": "s"},
	{"id": "WW_N3", "x": -56.0, "z": 24.5, "w": 10.0, "d": 11.0, "floors": 3, "palette": "plaster_sand", "face": "s"},
	{"id": "WW_N4", "x": -67.5, "z": 24.5, "w": 10.0, "d": 11.0, "floors": 4, "palette": "plaster_cream", "face": "s"},
	{"id": "WW_N5", "x": -79.0, "z": 24.5, "w": 10.0, "d": 11.0, "floors": 2, "palette": "plaster_sand", "face": "s"},
	{"id": "WW_S1", "x": -32.5, "z": 44.0, "w": 10.0, "d": 11.0, "floors": 3, "palette": "plaster_cream", "face": "n"},
	{"id": "WW_S2", "x": -44.5, "z": 44.0, "w": 10.0, "d": 11.0, "floors": 2, "palette": "plaster_sand", "face": "n"},
	{"id": "WW_S3", "x": -56.0, "z": 44.0, "w": 10.0, "d": 11.0, "floors": 4, "palette": "plaster_pink", "face": "n"},
	{"id": "WW_S4", "x": -67.5, "z": 44.0, "w": 10.0, "d": 11.0, "floors": 3, "palette": "plaster_white", "face": "n"},
	{"id": "WW_S5", "x": -79.0, "z": 44.0, "w": 10.0, "d": 11.0, "floors": 2, "palette": "brick", "face": "n"},
]

## 四向 EDAA 力场幕墙（2026-09-27 机主裁决：全部统一为《半衰期2》联合军式蓝色力场 +
## 马路延伸进夜雾；北 z=-95 / 南 z=+68 / 东西 x=±38.5，四向对称封闭街区）
## palette 缺省 rust_metal；tip_glow=true 时顶部加 EDAA 蓝色发光帽
const BARRIERS := [
	{"id": "FIELD", "x": 0.0, "z": -95.0, "w": 13.2, "d": 0.15, "h": 4.2, "palette": "edaa_field"},
	{"id": "FIELD_RAIL", "x": 0.0, "z": -95.0, "w": 13.2, "d": 0.35, "h": 0.18, "palette": "metal_dark"},
	{"id": "PYLON_W", "x": -6.8, "z": -95.0, "w": 0.55, "d": 0.55, "h": 4.6, "palette": "metal_dark", "tip_glow": true},
	{"id": "PYLON_E", "x": 6.8, "z": -95.0, "w": 0.55, "d": 0.55, "h": 4.6, "palette": "metal_dark", "tip_glow": true},
	# —— 南端（南延走廊，SF_W2/SF_E2 两翼贴楼夹持）——
	{"id": "FIELD_S", "x": 0.0, "z": 68.0, "w": 13.2, "d": 0.15, "h": 4.2, "palette": "edaa_field"},
	{"id": "FIELD_S_RAIL", "x": 0.0, "z": 68.0, "w": 13.2, "d": 0.35, "h": 0.18, "palette": "metal_dark"},
	{"id": "PYLON_SW", "x": -6.8, "z": 68.0, "w": 0.55, "d": 0.55, "h": 4.6, "palette": "metal_dark", "tip_glow": true},
	{"id": "PYLON_SE", "x": 6.8, "z": 68.0, "w": 0.55, "d": 0.55, "h": 4.6, "palette": "metal_dark", "tip_glow": true},
	# —— 东西端（横街延伸段，EW 楼排间隙夹持；幕墙沿 Z 跨走廊全宽）——
	{"id": "FIELD_E", "x": 38.5, "z": 34.25, "w": 0.15, "d": 11.0, "h": 4.2, "palette": "edaa_field"},
	{"id": "FIELD_E_RAIL", "x": 38.5, "z": 34.25, "w": 0.35, "d": 11.0, "h": 0.18, "palette": "metal_dark"},
	{"id": "PYLON_EN", "x": 38.5, "z": 28.6, "w": 0.55, "d": 0.55, "h": 4.6, "palette": "metal_dark", "tip_glow": true},
	{"id": "PYLON_ES", "x": 38.5, "z": 39.9, "w": 0.55, "d": 0.55, "h": 4.6, "palette": "metal_dark", "tip_glow": true},
	{"id": "FIELD_W", "x": -38.5, "z": 34.25, "w": 0.15, "d": 11.0, "h": 4.2, "palette": "edaa_field"},
	{"id": "FIELD_W_RAIL", "x": -38.5, "z": 34.25, "w": 0.35, "d": 11.0, "h": 0.18, "palette": "metal_dark"},
	{"id": "PYLON_WN", "x": -38.5, "z": 28.6, "w": 0.55, "d": 0.55, "h": 4.6, "palette": "metal_dark", "tip_glow": true},
	{"id": "PYLON_WS", "x": -38.5, "z": 39.9, "w": 0.55, "d": 0.55, "h": 4.6, "palette": "metal_dark", "tip_glow": true},
]

## 背景楼群填充分区（2026-09-27 机主裁决：填满临街排楼背后的空白虚空）
## rect=[x0, z0, x1, z1] 楼块填充范围；ground_rect=地面石板覆盖范围（消地面虚空，缺省=rect）
## builder 定种子随机落块（城中村肌理夜景剪影，无立面套件）；巷弄院落/建筑/围挡自动避让
## block=块尺寸范围，floors=层数范围，gap=块间距，density=放置概率
## 2026-09-27 大排查：地面铺装全面内推到人行道边 x=±6.5（两翼不再有泥地接缝）；
## 横街以南重排为远端（栅栏门后）+ 近端（南延走廊两翼）四分区，z/x 边界精确对接不重叠
const BACKFILL_ZONES := [
	# 西/东两翼近景（临街排楼背后；地面贴到人行道边，楼间缝隙全铺装；
	# 密度 0.97/间距 2.2 —— 二次裁决：填密减少镂空缝隙）
	{"rect": [-42.0, -92.0, -17.5, 30.0], "ground_rect": [-42.0, -92.0, -6.5, 30.0], "block": [8.0, 12.0], "floors": [2, 5], "gap": 2.2, "density": 0.97},
	{"rect": [17.5, -92.0, 42.0, 30.0], "ground_rect": [6.5, -92.0, 42.0, 30.0], "block": [8.0, 12.0], "floors": [2, 5], "gap": 2.2, "density": 0.97},
	# 横街以南远端（东西力场幕墙后）
	{"rect": [-42.0, 30.0, -26.5, 102.0], "block": [9.0, 13.0], "floors": [2, 4], "gap": 3.0, "density": 0.9},
	{"rect": [26.5, 30.0, 42.0, 102.0], "block": [9.0, 13.0], "floors": [2, 4], "gap": 3.0, "density": 0.9},
	# 横街以南近端（南延走廊两翼；块从 z=39.3 起避开横街人行道，S/SF 楼 footprint 自动避让）
	{"rect": [-26.5, 39.3, -6.5, 100.0], "ground_rect": [-26.5, 38.5, -6.5, 102.0], "block": [9.0, 13.0], "floors": [2, 4], "gap": 3.0, "density": 0.9},
	{"rect": [6.5, 39.3, 26.5, 100.0], "ground_rect": [6.5, 38.5, 26.5, 102.0], "block": [9.0, 13.0], "floors": [2, 4], "gap": 3.0, "density": 0.9},
	# 横街东西延伸段两翼（力场后的走廊纵深；EW/WW 夹道楼 footprint 自动避让）
	{"rect": [42.0, -30.0, 96.0, 29.0], "block": [8.0, 12.0], "floors": [2, 5], "gap": 2.5, "density": 0.92},
	{"rect": [42.0, 38.5, 96.0, 64.0], "block": [9.0, 13.0], "floors": [2, 4], "gap": 3.0, "density": 0.9},
	{"rect": [-96.0, -30.0, -42.0, 29.0], "block": [8.0, 12.0], "floors": [2, 5], "gap": 2.5, "density": 0.92},
	{"rect": [-96.0, 38.5, -42.0, 64.0], "block": [9.0, 13.0], "floors": [2, 4], "gap": 3.0, "density": 0.9},
	# 力场以北远景：楼块退居雾中楼排背后；地面石板贴到人行道边（路肩无虚空）
	{"rect": [-42.0, -158.0, -17.5, -93.5], "ground_rect": [-42.0, -160.0, -6.5, -92.0], "block": [9.0, 14.0], "floors": [3, 7], "gap": 3.0, "density": 0.8},
	{"rect": [17.5, -158.0, 42.0, -93.5], "ground_rect": [6.5, -160.0, 42.0, -92.0], "block": [9.0, 14.0], "floors": [3, 7], "gap": 3.0, "density": 0.8},
]

## 巷弄生活道具（RE3 重制版式街区丰富度；type 决定 builder 的装配方式）
## rot_y 为度；y 为落脚面高度（人行道 0.145 / 巷院地面 0.07）；bistro_set = 圆桌+双椅+遮阳伞一体
const PROPS := [
	# 篮球场院落（WB 巷尾）：半场单架 + 散落篮球
	{"type": "basket_hoop", "x": -26.0, "z": -59.0, "y": 0.07, "rot_y": 90.0},
	{"type": "basketball", "x": -23.5, "z": -61.5, "y": 0.07, "rot_y": 0.0},
	# 露天小酒馆（EA 巷尾院落）：三套桌椅伞
	{"type": "bistro_set", "x": 21.5, "z": -24.0, "y": 0.07, "rot_y": 0.0},
	{"type": "bistro_set", "x": 24.5, "z": -28.5, "y": 0.07, "rot_y": 40.0},
	{"type": "bistro_set", "x": 21.0, "z": -33.0, "y": 0.07, "rot_y": -30.0},
	# 靠墙停放的自行车（巷口/墙根）
	{"type": "bike", "x": -6.15, "z": -28.5, "y": 0.145, "rot_y": 90.0},
	{"type": "bike", "x": -6.15, "z": -30.2, "y": 0.145, "rot_y": 90.0},
	{"type": "bike", "x": 6.15, "z": -25.5, "y": 0.145, "rot_y": -90.0},
	{"type": "bike", "x": -6.15, "z": -58.0, "y": 0.145, "rot_y": 90.0},
	{"type": "bike", "x": 6.15, "z": -57.0, "y": 0.145, "rot_y": -90.0},
	# 垃圾桶散布
	{"type": "trash_bin", "x": -6.0, "z": -33.5, "y": 0.145, "rot_y": 15.0},
	{"type": "trash_bin", "x": 6.2, "z": -55.5, "y": 0.145, "rot_y": -20.0},
	{"type": "trash_bin", "x": -18.5, "z": -30.5, "y": 0.07, "rot_y": 0.0},
	{"type": "trash_bin", "x": 20.0, "z": -35.5, "y": 0.07, "rot_y": 55.0},
]

## 可进入建筑室内家具（2026-09-30 机主立项：E1 内饰试点；Blender 烘焙 fur_* 套件）
## bldg 对应 BUILDINGS id；y 为落脚面（E1 一楼 0.145 / 二楼 3.0）；rot_y=0 时正面朝 +Z（南）
## E1 布局：一楼门厅（西，客厅）| 东房（卧室，Host_F1）；二楼楼梯间 | 南房（卧室，Host_F2）
## 摆位纪律：楼梯段/转角平台/门板正前方与 Host 巡逻中轴留空，家具贴墙落位
const FURNITURE := [
	# —— E1 一楼门厅（客厅）：沙发朝东对电视柜，茶几居中，置物架贴南墙 ——
	{"bldg": "E1", "type": "sofa", "x": 7.55, "z": 20.3, "y": 0.145, "rot_y": 90.0},
	{"bldg": "E1", "type": "tv_stand", "x": 10.55, "z": 20.3, "y": 0.145, "rot_y": -90.0},
	{"bldg": "E1", "type": "table", "x": 9.0, "z": 20.3, "y": 0.145, "rot_y": 0.0},
	{"bldg": "E1", "type": "shelf", "x": 10.45, "z": 22.35, "y": 0.145, "rot_y": 180.0},
	# —— E1 一楼东房（卧室）：床贴东墙床头朝北，衣柜贴北墙，床头柜床侧，桌椅靠南 ——
	{"bldg": "E1", "type": "bed", "x": 15.5, "z": 14.9, "y": 0.145, "rot_y": 0.0},
	{"bldg": "E1", "type": "wardrobe", "x": 12.4, "z": 13.65, "y": 0.145, "rot_y": 0.0},
	{"bldg": "E1", "type": "nightstand", "x": 15.55, "z": 16.6, "y": 0.145, "rot_y": -90.0},
	{"bldg": "E1", "type": "table", "x": 12.6, "z": 21.6, "y": 0.145, "rot_y": 0.0},
	{"bldg": "E1", "type": "chair", "x": 12.6, "z": 20.7, "y": 0.145, "rot_y": 0.0},
	# —— E1 二楼南房（卧室）：床贴南墙床头朝西，衣柜贴东墙，置物架贴西墙，床头柜床侧 ——
	{"bldg": "E1", "type": "bed", "x": 8.7, "z": 22.1, "y": 3.0, "rot_y": 90.0},
	{"bldg": "E1", "type": "nightstand", "x": 10.15, "z": 22.3, "y": 3.0, "rot_y": 180.0},
	{"bldg": "E1", "type": "wardrobe", "x": 15.75, "z": 20.0, "y": 3.0, "rot_y": -90.0},
	{"bldg": "E1", "type": "shelf", "x": 12.8, "z": 22.54, "y": 3.0, "rot_y": 180.0},  # 2026-10-07 机主验收：原西墙位挡阳台门洞（z 19.05..19.95），挪南墙
	# —— E2（3 层直上，2026-10-07 机主裁决：一栋装不下的陈设分到第二栋，含 2 楼以上）——
	# E2 内空 x 6.8..16.2 / z -9.7..1.7；楼梯占西北角（z -9.7..-4.95）；一层隔断 x=11.0 门洞 z -3.0..-1.8；
	# 上层隔断 z=-3.5 门洞 x 10.9..12.1（北=楼梯间留空巡逻，南=南房）
	# F1 门厅（客厅，楼梯以南）：沙发朝东对电视柜，茶几居中，置物架贴南墙
	{"bldg": "E2", "type": "sofa", "x": 7.55, "z": -0.8, "y": 0.145, "rot_y": 90.0},
	{"bldg": "E2", "type": "tv_stand", "x": 10.55, "z": -0.8, "y": 0.145, "rot_y": -90.0},
	{"bldg": "E2", "type": "table", "x": 9.0, "z": -0.8, "y": 0.145, "rot_y": 0.0},
	{"bldg": "E2", "type": "shelf", "x": 10.45, "z": 1.35, "y": 0.145, "rot_y": 180.0},
	# F1 东房（卧室）：床贴东墙床头朝北，衣柜贴北墙，床头柜床侧，桌椅靠南
	{"bldg": "E2", "type": "bed", "x": 15.5, "z": -8.0, "y": 0.145, "rot_y": 0.0},
	{"bldg": "E2", "type": "wardrobe", "x": 12.4, "z": -9.35, "y": 0.145, "rot_y": 0.0},
	{"bldg": "E2", "type": "nightstand", "x": 15.55, "z": -6.3, "y": 0.145, "rot_y": -90.0},
	{"bldg": "E2", "type": "table", "x": 12.6, "z": -0.3, "y": 0.145, "rot_y": 0.0},
	{"bldg": "E2", "type": "chair", "x": 12.6, "z": -1.2, "y": 0.145, "rot_y": 0.0},
	# F2 南房（卧室）：床贴南墙床头朝西，衣柜贴东墙，置物架贴西墙，床头柜床侧
	{"bldg": "E2", "type": "bed", "x": 8.7, "z": 1.1, "y": 3.0, "rot_y": 90.0},
	{"bldg": "E2", "type": "nightstand", "x": 10.15, "z": 1.3, "y": 3.0, "rot_y": 180.0},
	{"bldg": "E2", "type": "wardrobe", "x": 15.75, "z": -1.0, "y": 3.0, "rot_y": -90.0},
	{"bldg": "E2", "type": "shelf", "x": 12.8, "z": 1.54, "y": 3.0, "rot_y": 180.0},  # 2026-10-07 机主验收：原西墙位挡阳台门洞（z -2.95..-2.05），挪南墙
	# F3 南房（卧室，顶楼）：床贴南墙床头朝西，床头柜床侧，桌椅靠隔断
	{"bldg": "E2", "type": "bed", "x": 8.7, "z": 1.1, "y": 6.0, "rot_y": 90.0},
	{"bldg": "E2", "type": "nightstand", "x": 10.15, "z": 1.3, "y": 6.0, "rot_y": 180.0},
	{"bldg": "E2", "type": "table", "x": 12.6, "z": -0.5, "y": 6.0, "rot_y": 0.0},
	{"bldg": "E2", "type": "chair", "x": 12.6, "z": -1.4, "y": 6.0, "rot_y": 0.0},
]

## 室内细节件（2026-10-07 道具批2「画皮居所」叙事陈设；Blender 烘焙 dec_* 套件）
## bldg/type/x/z/y/rot_y 语义同 FURNITURE，但 builder 走【直接落位】而非 _prop_model：
##   dec_* 已在烘焙期定死真实尺寸与「落地/贴墙」原点，再做 AABB 归一缩放会把件二次缩放、
##   并把贴墙件的背面拉离墙面（见 street_builder._furnish_decor 注释）。
## 朝向：rot_y=0 时件正面朝 +Z（南）；贴墙件背面贴墙、件向室内凸出，故
##   北墙 rot_y=0 ｜ 南墙 rot_y=180 ｜ 西墙 rot_y=90 ｜ 东墙 rot_y=-90。
## y：地面件 = 楼层地面高（F1 0.145 / F2 3.0 / F3 6.0）；桌面件 = 家具顶面高（茶几 0.145+0.75）；
##    贴墙件 = 件底边高。纪律同 FURNITURE：楼梯段/平台/门洞正前方/Host 巡逻中轴留空。
const DECOR := [
	# —— E1 一楼门厅（客厅，西区）：茶几桌面餐具 + 南墙挂墙工装（贴墙件避开货架 x 10.05..10.85）——
	{"bldg": "E1", "type": "tableware", "x": 9.0, "z": 20.3, "y": 0.895, "rot_y": 0.0},
	{"bldg": "E1", "type": "mug", "x": 9.42, "z": 20.52, "y": 0.895, "rot_y": 0.0},
	{"bldg": "E1", "type": "jacket", "x": 8.2, "z": 22.67, "y": 1.3, "rot_y": 180.0},
	# —— E1 一楼东房（卧室，Host_F1）：安全帽落地 + 人字拖床边 + 北墙轮值表（避开衣柜 x 11.78..13.03）——
	{"bldg": "E1", "type": "helmet", "x": 13.5, "z": 21.9, "y": 0.145, "rot_y": 0.0},
	{"bldg": "E1", "type": "slippers", "x": 14.55, "z": 15.4, "y": 0.145, "rot_y": 0.0},
	{"bldg": "E1", "type": "roster", "x": 13.6, "z": 13.33, "y": 1.35, "rot_y": 0.0},
	# —— E2（3 层直上，同款语言三层铺开：看守据点，层层都有生活痕迹，层层都没人）——
	# F1 门厅：茶几餐具 + 搪瓷杯，南墙工装（避开货架 x 10.05..10.85），西墙轮值表
	{"bldg": "E2", "type": "tableware", "x": 9.0, "z": -0.8, "y": 0.895, "rot_y": 0.0},
	{"bldg": "E2", "type": "mug", "x": 9.42, "z": -0.58, "y": 0.895, "rot_y": 0.0},
	{"bldg": "E2", "type": "jacket", "x": 8.2, "z": 1.67, "y": 1.3, "rot_y": 180.0},
	{"bldg": "E2", "type": "roster", "x": 6.83, "z": -1.0, "y": 1.35, "rot_y": 90.0},
	# F1 东房（Host_E2_F1）：安全帽落地（床与隔断间空地）+ 人字拖床尾 + 北墙轮值表（避开衣柜）
	{"bldg": "E2", "type": "helmet", "x": 14.5, "z": -5.5, "y": 0.145, "rot_y": 0.0},
	{"bldg": "E2", "type": "slippers", "x": 14.55, "z": -6.6, "y": 0.145, "rot_y": 0.0},
	{"bldg": "E2", "type": "roster", "x": 13.6, "z": -9.67, "y": 1.35, "rot_y": 0.0},
	# F2 南房：床头柜搪瓷杯 + 床边人字拖
	{"bldg": "E2", "type": "mug", "x": 10.15, "z": 1.3, "y": 3.48, "rot_y": 0.0},
	{"bldg": "E2", "type": "slippers", "x": 9.6, "z": 0.45, "y": 3.0, "rot_y": 90.0},
	# F3 南房（顶楼）：安全帽落地（床东北角）+ 床边人字拖
	{"bldg": "E2", "type": "helmet", "x": 10.3, "z": 0.6, "y": 6.0, "rot_y": 0.0},
	{"bldg": "E2", "type": "slippers", "x": 9.6, "z": 0.45, "y": 6.0, "rot_y": -90.0},
]

## 室内拾取物（2026-10-07 机主裁决：电池组 / 医疗注射 / 取证终端三类，无 RPG）
## kind = battery（步枪备弹 +GameConfig.BATTERY_PICKUP_ROUNDS）
##      / medkit（注射 +1，携带上限 MEDKIT_MAX_CARRY）
##      / intel（取证终端，叙事收集品；本图总数 = 本表 intel 条目数，由 builder 注入 intel_total）
## y 为视觉悬浮位（落面 +0.105 左右防穿面，配合 pickup.gd 浮动自转；床上件略沉入床垫更自然）。
## E1+E2 各三件，电池组放 E2 三楼引玩家爬满全楼。
const PICKUPS := [
	# —— E1：茶几电池组、东房桌取证终端（与碗筷错开）、F2 床上医疗注射 ——
	{"bldg": "E1", "kind": "battery", "x": 9.1, "y": 1.0, "z": 20.5},
	{"bldg": "E1", "kind": "intel", "x": 13.0, "y": 1.0, "z": 21.7},
	{"bldg": "E1", "kind": "medkit", "x": 8.6, "y": 3.62, "z": 22.05},
	# —— E2：F1 东房桌取证终端、F2 床上医疗注射、F3 桌电池组 ——
	{"bldg": "E2", "kind": "intel", "x": 13.0, "y": 1.0, "z": -0.55},
	{"bldg": "E2", "kind": "medkit", "x": 8.6, "y": 3.62, "z": 1.0},
	{"bldg": "E2", "kind": "battery", "x": 12.6, "y": 6.86, "z": -0.4},
]
