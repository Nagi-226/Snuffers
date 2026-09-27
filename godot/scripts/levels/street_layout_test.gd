class_name StreetLayoutTest
extends RefCounted

## P0 试验街布局数据表 — 借鉴 Claude-of-Duty layout.js 的声明式范式（见文档10 §1-P0）
## 整张街区 = 本表；builder（street_builder.gd）只解释数据，不硬编码任何尺寸。
## 坐标系: 主街沿 Z 轴（-Z 为远），X 为横向。单位: 米。

const STREET := {
	"half_width": 4.5,   # 沥青路面半宽
	"kerb": 6.5,         # 建筑线（人行道外缘）
	"walk_h": 0.145,     # 人行道抬高
	"z_min": -40.0,
	"z_max": 30.0,
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
const ALLEYS := [
	{"rect": [-20.0, -12.0, -6.5, -8.0], "surface": "dirt"},    # 西侧巷道
	{"rect": [6.5, 2.0, 22.0, 8.0], "surface": "gravel"},        # 东侧 flank 巷
	{"rect": [-22.0, 14.0, -6.5, 20.0], "surface": "dirt"},      # 西侧院落
]

## 建筑: x/z 为体块中心，w=X 向宽，d=Z 向深，floors 层数，palette 为调色板键
## face 为立面朝向（"n"=朝北 -Z），缺省按旧规则（西排朝东/东排朝西/门楼朝南）
## 西排（x<0）与东排（x>0）贴建筑线布置
const BUILDINGS := [
	{"id": "W1", "x": -11.5, "z": 23.0, "w": 10.0, "d": 12.0, "floors": 2, "palette": "plaster_cream"},
	{"id": "W2", "x": -11.5, "z": 10.0, "w": 10.0, "d": 14.0, "floors": 3, "palette": "plaster_sand"},
	{"id": "W3", "x": -11.5, "z": -2.0, "w": 10.0, "d": 10.0, "floors": 2, "palette": "plaster_white"},
	{"id": "W4", "x": -11.5, "z": -20.0, "w": 10.0, "d": 14.0, "floors": 3, "palette": "brick"},
	{"id": "E1", "x": 11.5, "z": 18.0, "w": 10.0, "d": 10.0, "floors": 2, "palette": "plaster_pink"},
	{"id": "E2", "x": 11.5, "z": -4.0, "w": 10.0, "d": 12.0, "floors": 3, "palette": "plaster_sand"},
	{"id": "E3", "x": 11.5, "z": -18.0, "w": 10.0, "d": 12.0, "floors": 2, "palette": "plaster_cream"},
	# 远端封景门楼（横跨街道，closing the far vista；锈蚀金属验证件）
	{"id": "GATE", "x": 0.0, "z": -38.0, "w": 18.0, "d": 4.0, "floors": 2, "palette": "rust_metal"},
	# 横街南排（面朝北，临横街；T 字路口的临街面）
	{"id": "S1", "x": -15.0, "z": 43.5, "w": 12.0, "d": 10.0, "floors": 3, "palette": "plaster_sand", "face": "n"},
	{"id": "S2", "x": 0.0, "z": 43.5, "w": 14.0, "d": 10.0, "floors": 2, "palette": "plaster_cream", "face": "n"},
	{"id": "S3", "x": 15.0, "z": 43.5, "w": 12.0, "d": 10.0, "floors": 3, "palette": "plaster_pink", "face": "n"},
]

## 横街两端铁栅栏门（分段加载气闸占位，文档11 §6.6；正式栅栏门件待道具批2烘焙）
const BARRIERS := [
	{"id": "GATE_WEST", "x": -27.2, "z": 34.0, "w": 2.4, "d": 9.0, "h": 3.5},
	{"id": "GATE_EAST", "x": 27.2, "z": 34.0, "w": 2.4, "d": 9.0, "h": 3.5},
]
