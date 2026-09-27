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
## 主街 z_max 处转为东西向横街，两端铁栅栏门封死 = 未来分段加载气闸占位）
const CROSS := {
	"z_min": 30.0,       # 横街沥青北缘（接主街断头处）
	"z_max": 36.5,       # 横街沥青南缘
	"x_min": -26.0,      # 西端栅栏门位
	"x_max": 26.0,       # 东端栅栏门位
	"walk_south_z": 38.5, # 南侧人行道南缘（建筑线）
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
	{"id": "E1", "x": 11.5, "z": 18.0, "w": 10.0, "d": 10.0, "floors": 2, "palette": "plaster_pink"},
	{"id": "E2", "x": 11.5, "z": -4.0, "w": 10.0, "d": 12.0, "floors": 3, "palette": "plaster_sand"},
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
	# 横街南排（面朝北，临横街；T 字路口的临街面）
	{"id": "S1", "x": -15.0, "z": 43.5, "w": 12.0, "d": 10.0, "floors": 3, "palette": "plaster_sand", "face": "n"},
	{"id": "S2", "x": 0.0, "z": 43.5, "w": 14.0, "d": 10.0, "floors": 2, "palette": "plaster_cream", "face": "n"},
	{"id": "S3", "x": 15.0, "z": 43.5, "w": 12.0, "d": 10.0, "floors": 3, "palette": "plaster_pink", "face": "n"},
]

## 横街两端铁栅栏门（分段加载气闸占位，文档11 §6.6；正式栅栏门件待道具批2烘焙）
## palette 缺省 rust_metal；hazard=true 时顶部加红色警示灯条；tip_glow=true 时顶部加 EDAA 蓝色发光帽
const BARRIERS := [
	{"id": "GATE_WEST", "x": -27.2, "z": 34.0, "w": 2.4, "d": 9.0, "h": 3.5},
	{"id": "GATE_EAST", "x": 27.2, "z": 34.0, "w": 2.4, "d": 9.0, "h": 3.5},
	# —— 北端 EDAA 能量屏蔽力场（2026-09-27 机主裁决：弃水泥隔离墩，
	#     改《半衰期2》联合军式蓝色高科技力场；路面向北延伸 64m 没入夜雾）——
	{"id": "FIELD", "x": 0.0, "z": -95.0, "w": 13.2, "d": 0.15, "h": 4.2, "palette": "edaa_field"},
	{"id": "FIELD_RAIL", "x": 0.0, "z": -95.0, "w": 13.2, "d": 0.35, "h": 0.18, "palette": "metal_dark"},
	{"id": "PYLON_W", "x": -6.8, "z": -95.0, "w": 0.55, "d": 0.55, "h": 4.6, "palette": "metal_dark", "tip_glow": true},
	{"id": "PYLON_E", "x": 6.8, "z": -95.0, "w": 0.55, "d": 0.55, "h": 4.6, "palette": "metal_dark", "tip_glow": true},
]

## 背景楼群填充分区（2026-09-27 机主裁决：填满临街排楼背后的空白虚空）
## rect=[x0, z0, x1, z1] 填充范围；builder 定种子随机落块（城中村肌理夜景剪影，无立面套件）
## 巷弄院落/T字横街自动避让；block=块尺寸范围，floors=层数范围，gap=块间距，density=放置概率
const BACKFILL_ZONES := [
	# 西/东两翼近景（临街排楼背后）
	{"rect": [-42.0, -92.0, -17.5, 48.0], "block": [8.0, 12.0], "floors": [2, 5], "gap": 2.5, "density": 0.95},
	{"rect": [17.5, -92.0, 42.0, 48.0], "block": [8.0, 12.0], "floors": [2, 5], "gap": 2.5, "density": 0.95},
	# 横街以南（T 字路口对面的纵深）
	{"rect": [-30.0, 49.0, 30.0, 72.0], "block": [9.0, 13.0], "floors": [2, 4], "gap": 3.0, "density": 0.9},
	# 力场以北远景（贴路沿排布，街道没入雾中的纵深错觉；外侧稀疏高层剪影）
	{"rect": [-42.0, -158.0, -7.5, -93.5], "block": [9.0, 14.0], "floors": [3, 7], "gap": 3.0, "density": 0.8},
	{"rect": [7.5, -158.0, 42.0, -93.5], "block": [9.0, 14.0], "floors": [3, 7], "gap": 3.0, "density": 0.8},
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
