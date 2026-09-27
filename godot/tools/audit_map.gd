extends SceneTree
## 全图封闭性/立面审计工具（2026-09-27 机主裁决：全图排查漏封与缺立面）
## 用法: godot --headless --path . --script tools/audit_map.gd
## 实例化真实 street_test 场景，收集全部碰撞盒后做三项审计：
##   A. 可达性洪水填充：从街心 BFS，可达但不在预期可玩区内的格子 = 漏封缺口
##   B. 栅栏视线封闭：每段铁栅栏向外 8m 内无墙/楼/背景楼遮挡 = 视线泄漏到虚空
##   C. 立面缺失：排楼凡是面贴可达区的墙面，必须有立面套件件（门窗），否则报缺

const CELL := 0.25
const GX0 := -100.0
const GZ0 := -165.0
const GW := 800    # x -100..100
const GH := 1100   # z -165..110
const PLAYER_R := 0.35

var _blocked := PackedByteArray()
var _reach := PackedByteArray()
var _intended: Array = []   # 预期可玩区 rect 列表
var _paved: Array = []      # 铺装面 rect 列表
var _cols := []             # {rect:[x0,z0,x1,z1], y0, y1, tag}
var _walls := []            # 砖墙 {axis,pos,from,to}
var _fences := []           # 铁栅栏 {axis,pos,from,to}
var _bldgs := []            # {id, rect}
var _kit_pts := []          # 立面件世界坐标（原点在墙面上）


func _pt_in_rect(px: float, pz: float, r: Array) -> bool:
	return px > r[0] and px < r[2] and pz > r[1] and pz < r[3]


## 2D 射线 vs rect（slab 法）：命中返回距离（0..max_d），未命中返回 -1
func _ray_rect_dist(o: Vector2, d: Vector2, max_d: float, r: Array) -> float:
	var tmin := 0.0
	var tmax := max_d
	for axis in 2:
		var p: float = o.x if axis == 0 else o.y
		var dv: float = d.x if axis == 0 else d.y
		var r0: float = r[0] if axis == 0 else r[1]
		var r1: float = r[2] if axis == 0 else r[3]
		if absf(dv) < 0.0001:
			if p < r0 or p > r1:
				return -1.0
		else:
			var t1 := (r0 - p) / dv
			var t2 := (r1 - p) / dv
			if t1 > t2:
				var tmp := t1
				t1 = t2
				t2 = tmp
			tmin = maxf(tmin, t1)
			tmax = minf(tmax, t2)
			if tmin > tmax:
				return -1.0
	return tmin


func _cell_idx(px: float, pz: float) -> int:
	var ix := int(floor((px - GX0) / CELL))
	var iz := int(floor((pz - GZ0) / CELL))
	if ix < 0 or ix >= GW or iz < 0 or iz >= GH:
		return -1
	return iz * GW + ix


## 收集盒体碰撞：8 角点变换求世界 AABB（仅 90° 旋转，AABB 精确）
## tag 取有效名：碰撞体默认名 StaticBody3D 时向上取 holder 名（Fence_*/Prop_* 可分辨）
func _collect_boxes(n: Node, group: String) -> void:
	if n is StaticBody3D:
		var eff_name := n.name
		var p := n.get_parent()
		while eff_name == "StaticBody3D" and p != null:
			eff_name = p.name
			p = p.get_parent()
		for c in n.get_children():
			if c is CollisionShape3D and c.shape is BoxShape3D:
				var half: Vector3 = (c.shape as BoxShape3D).size * 0.5
				var gt: Transform3D = c.global_transform
				var mn := Vector3(INF, INF, INF)
				var mx := Vector3(-INF, -INF, -INF)
				for sx in [-1.0, 1.0]:
					for sy in [-1.0, 1.0]:
						for sz in [-1.0, 1.0]:
							var p8: Vector3 = gt * Vector3(half.x * sx, half.y * sy, half.z * sz)
							mn = mn.min(p8)
							mx = mx.max(p8)
				var tag := "%s/%s" % [group, eff_name]
				_cols.append({"rect": [mn.x, mn.z, mx.x, mx.z], "y0": mn.y, "y1": mx.y, "tag": tag})
				if group == "Barriers" and eff_name.begins_with("Wall_"):
					if mx.x - mn.x < mx.z - mn.z:
						_walls.append({"axis": 0, "pos": (mn.x + mx.x) * 0.5, "from": mn.z, "to": mx.z})
					else:
						_walls.append({"axis": 1, "pos": (mn.z + mx.z) * 0.5, "from": mn.x, "to": mx.x})
	for c in n.get_children():
		_collect_boxes(c, group)


## 栅栏 holder（Node3D，名 Fence_*）的碰撞在子 StaticBody3D 上；从碰撞盒反推轴线
func _collect_fences(row: Node) -> void:
	for h in row.get_children():
		if not h.name.begins_with("Fence_"):
			continue
		for body in h.get_children():
			if body is StaticBody3D:
				for c in body.get_children():
					if c is CollisionShape3D and c.shape is BoxShape3D:
						var half: Vector3 = (c.shape as BoxShape3D).size * 0.5
						var gt: Transform3D = c.global_transform
						var mn := Vector3(INF, INF, INF)
						var mx := Vector3(-INF, -INF, -INF)
						for sx in [-1.0, 1.0]:
							for sy in [-1.0, 1.0]:
								for sz in [-1.0, 1.0]:
									var p: Vector3 = gt * Vector3(half.x * sx, half.y * sy, half.z * sz)
									mn = mn.min(p)
									mx = mx.max(p)
						if mx.x - mn.x < mx.z - mn.z:
							_fences.append({"axis": 0, "pos": (mn.x + mx.x) * 0.5, "from": mn.z, "to": mx.z})
						else:
							_fences.append({"axis": 1, "pos": (mn.z + mx.z) * 0.5, "from": mn.x, "to": mx.x})


func _collect_kit_pts(row: Node) -> void:
	for ch in row.get_children():
		if ch.name.begins_with("Bldg_"):
			continue
		if ch is Node3D:  # 套件件实例（原点贴墙面）
			_kit_pts.append((ch as Node3D).global_position)


func _init() -> void:
	_run()  # 协程：等一帧让 builder._ready 完成建模后再审计


func _run() -> void:
	_blocked.resize(GW * GH)
	_reach.resize(GW * GH)

	var L: GDScript = load("res://scripts/levels/street_layout_test.gd")
	var s: Dictionary = L.STREET
	var c: Dictionary = L.CROSS
	var se: Dictionary = L.SOUTH_EXT

	# —— 预期可玩区（builder._coverage_rects + 横街北人行道）——
	_intended = [
		[-s["kerb"], s["z_min"], s["kerb"], s["z_max"]],
		[-s["kerb"], s["z_max"], s["kerb"], se["z_max"]],
		[c["x_min"], c["z_min"], c["x_max"], c["walk_south_z"]],
		[c["x_min"], c["walk_north_z"], c["x_max"], c["z_min"]],
	]
	for a in L.ALLEYS:
		_intended.append(a["rect"])
	# 可进入楼室内（壳体化后室内可达，属预期可玩区；墙厚 0.3 内推）
	for b in L.BUILDINGS:
		if b.get("enterable", false):
			_intended.append([b["x"] - b["w"] * 0.5 + 0.3, b["z"] - b["d"] * 0.5 + 0.3,
				b["x"] + b["w"] * 0.5 - 0.3, b["z"] + b["d"] * 0.5 - 0.3])

	# —— 铺装面（与 audit_ground 一致）——
	_paved = [
		[-s["half_width"], s["z_min"], s["half_width"], s["z_max"]],
		[-s["kerb"], s["z_min"], -s["half_width"], s["z_max"]],
		[s["half_width"], s["z_min"], s["kerb"], s["z_max"]],
		[c["x_min"], c["z_min"], c["x_max"], c["z_max"]],
		[c["x_min"], c["z_max"], -s["kerb"], c["walk_south_z"]],
		[s["kerb"], c["z_max"], c["x_max"], c["walk_south_z"]],
		[c["x_min"], c["walk_north_z"], -s["kerb"], c["z_min"]],
		[s["kerb"], c["walk_north_z"], c["x_max"], c["z_min"]],
		[-s["half_width"], se["z_min"], s["half_width"], se["z_max"]],
		[-s["kerb"], se["z_min"], -s["half_width"], se["z_max"]],
		[s["kerb"], se["z_min"], s["kerb"], se["z_max"]],
	]
	for a in L.ALLEYS:
		_paved.append(a["rect"])
	for z in L.BACKFILL_ZONES:
		_paved.append(z.get("ground_rect", z["rect"]))

	# —— 实例化真实场景收集几何（等两帧确保 _ready 建模完成）——
	var scene: Node3D = load("res://scenes/levels/street_test.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	for grp in ["Ground", "Buildings", "Backdrop", "Barriers", "Props"]:
		var node := scene.get_node_or_null(grp)
		if node:
			_collect_boxes(node, grp)
	var brow := scene.get_node_or_null("Buildings")
	if brow:
		_collect_kit_pts(brow)
	var barow := scene.get_node_or_null("Barriers")
	if barow:
		_collect_fences(barow)
	for b in L.BUILDINGS:
		_bldgs.append({"id": b["id"], "rect": [b["x"] - b["w"] * 0.5, b["z"] - b["d"] * 0.5,
			b["x"] + b["w"] * 0.5, b["z"] + b["d"] * 0.5]})
	print(" collected: cols=%d walls=%d fences=%d kit=%d" % [
		_cols.size(), _walls.size(), _fences.size(), _kit_pts.size()])

	# —— 栅格化障碍（y 与玩家躯干相交才挡）——
	for col in _cols:
		if col["y1"] < 0.3 or col["y0"] > 1.6:
			continue
		var r: Array = col["rect"]
		var ix0 := int(floor((r[0] - PLAYER_R - GX0) / CELL))
		var ix1 := int(floor((r[2] + PLAYER_R - GX0) / CELL))
		var iz0 := int(floor((r[1] - PLAYER_R - GZ0) / CELL))
		var iz1 := int(floor((r[3] + PLAYER_R - GZ0) / CELL))
		for iz in range(maxi(iz0, 0), mini(iz1, GH - 1) + 1):
			for ix in range(maxi(ix0, 0), mini(ix1, GW - 1) + 1):
				_blocked[iz * GW + ix] = 1

	# —— A. BFS 可达性 ——
	var start := _cell_idx(0.0, 20.0)
	var stack := [start]
	_reach[start] = 1
	var reach_count := 0
	while not stack.is_empty():
		var idx: int = stack.pop_back()
		reach_count += 1
		var ix := idx % GW
		var iz := idx / GW
		for d in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
			var nx: int = ix + d[0]
			var nz: int = iz + d[1]
			if nx < 0 or nx >= GW or nz < 0 or nz >= GH:
				continue
			var ni: int = nz * GW + nx
			if _blocked[ni] == 0 and _reach[ni] == 0:
				_reach[ni] = 1
				stack.append(ni)
	print("A. BFS 可达格子 %d（每格 %.2f m）" % [reach_count, CELL])

	# —— 可达但越界（漏封）聚簇 ——
	var leak_mark := PackedByteArray()
	leak_mark.resize(GW * GH)
	var leak_total := 0
	for iz in GH:
		for ix in GW:
			var idx := iz * GW + ix
			if _reach[idx] == 0:
				continue
			var px := GX0 + (float(ix) + 0.5) * CELL
			var pz := GZ0 + (float(iz) + 0.5) * CELL
			var ok := false
			for r in _intended:
				if _pt_in_rect(px, pz, r):
					ok = true
					break
			if not ok:
				leak_mark[idx] = 1
				leak_total += 1
	print("A. 漏封格子 %d" % leak_total)
	var cluster_id := 0
	var small_clusters := 0
	var small_cells := 0
	for iz in GH:
		for ix in GW:
			var idx := iz * GW + ix
			if leak_mark[idx] == 0:
				continue
			# 聚簇 BFS
			cluster_id += 1
			var q := [idx]
			leak_mark[idx] = 2
			var mnx := INF; var mxx := -INF; var mnz := INF; var mxz := -INF
			var cnt := 0
			while not q.is_empty():
				var cur: int = q.pop_back()
				cnt += 1
				var cx := cur % GW
				var cz := cur / GW
				var wx := GX0 + (float(cx) + 0.5) * CELL
				var wz := GZ0 + (float(cz) + 0.5) * CELL
				mnx = minf(mnx, wx); mxx = maxf(mxx, wx)
				mnz = minf(mnz, wz); mxz = maxf(mxz, wz)
				for d in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
					var nx2: int = cx + d[0]
					var nz2: int = cz + d[1]
					if nx2 < 0 or nx2 >= GW or nz2 < 0 or nz2 >= GH:
						continue
					var ni2: int = nz2 * GW + nx2
					if leak_mark[ni2] == 1:
						leak_mark[ni2] = 2
						q.append(ni2)
			if cnt >= 4:
				print("A. 漏封簇#%d 格子%d 范围 x[%.1f..%.1f] z[%.1f..%.1f]" % [
					cluster_id, cnt, mnx, mxx, mnz, mxz])
			else:
				small_clusters += 1
				small_cells += cnt
	if small_clusters > 0:
		print("A. 另有 %d 个微小簇（共 %d 格，<4 格不逐列）" % [small_clusters, small_cells])

	# —— B. 栅栏视线封闭（向外 8m 须有遮挡）——
	var sight_leaks := 0
	for f in _fences:
		# 判定外法向：两侧 0.6m 各取中点，落在预期可玩区的一侧为内
		var mid: float = (f["from"] + f["to"]) * 0.5
		var out_sign := 1.0
		var pa: Vector2; var pb: Vector2
		if f["axis"] == 0:
			pa = Vector2(f["pos"] - 0.6, mid); pb = Vector2(f["pos"] + 0.6, mid)
		else:
			pa = Vector2(mid, f["pos"] - 0.6); pb = Vector2(mid, f["pos"] + 0.6)
		var a_in := false
		for r in _intended:
			if _pt_in_rect(pa.x, pa.y, r):
				a_in = true
				break
		# axis=0 时 pa 在 -X 侧；a_in=true 说明内侧在 -X，外侧为 +X
		if a_in:
			out_sign = 1.0
		else:
			out_sign = -1.0
		var out_dir := Vector2(out_sign, 0.0) if f["axis"] == 0 else Vector2(0.0, out_sign)
		var t: float = f["from"] + 0.25
		var run_open := false
		var run_start := 0.0
		var leak_segs: Array = []
		while t < f["to"]:
			var origin := Vector2(f["pos"] + out_sign * 0.2, t) if f["axis"] == 0 \
				else Vector2(t, f["pos"] + out_sign * 0.2)
			var solid_d := INF
			for col in _cols:
				if col["y1"] < 1.0:
					continue
				var tag: String = col["tag"]
				var opaque: bool = tag.begins_with("Buildings/Bldg_") \
					or tag.begins_with("Backdrop/Backfill_") \
					or tag.begins_with("Barriers/Wall_") \
					or tag.begins_with("Ground/FIELD") or tag.begins_with("Ground/PYLON")
				if not opaque:
					continue
				var d := _ray_rect_dist(origin, out_dir, 8.0, col["rect"])
				if d >= 0.0 and d < solid_d:
					solid_d = d
			var cover_d := INF
			for r in _intended:
				var d2 := _ray_rect_dist(origin, out_dir, 8.0, r)
				if d2 >= 0.0 and d2 < cover_d:
					cover_d = d2
			var clear: bool = solid_d == INF and cover_d == INF
			if clear:
				if not run_open:
					run_open = true
					run_start = t
			elif run_open:
				leak_segs.append([run_start, t])
				run_open = false
			t += 0.5
		if run_open:
			leak_segs.append([run_start, f["to"]])
		for sg in leak_segs:
			if sg[1] - sg[0] < 0.6:
				continue
			sight_leaks += 1
			if f["axis"] == 0:
				print("B. 视线泄漏 栅栏 x=%.1f z[%.1f..%.1f] 外向%s 8m无遮挡" % [
					f["pos"], sg[0], sg[1], "+X" if out_sign > 0 else "-X"])
			else:
				print("B. 视线泄漏 栅栏 z=%.1f x[%.1f..%.1f] 外向%s 8m无遮挡" % [
					f["pos"], sg[0], sg[1], "+Z" if out_sign > 0 else "-Z"])
	print("B. 视线泄漏段 %d" % sight_leaks)

	# —— C. 立面缺失（面贴可达区的排楼墙面无套件件）——
	var face_dirs := [[1.0, 0.0], [-1.0, 0.0], [0.0, 1.0], [0.0, -1.0]]
	var undressed := 0
	for b in _bldgs:
		var r: Array = b["rect"]
		for fd in face_dirs:
			var out := Vector2(fd[0], fd[1])
			var face_pos: float
			var f0: float; var f1: float
			if out.x > 0.0:
				face_pos = r[2]; f0 = r[1]; f1 = r[3]
			elif out.x < 0.0:
				face_pos = r[0]; f0 = r[1]; f1 = r[3]
			elif out.y > 0.0:
				face_pos = r[3]; f0 = r[0]; f1 = r[2]
			else:
				face_pos = r[1]; f0 = r[0]; f1 = r[2]
			# 采样：面外 0.9m 是否可达；面外 0.45m 是否被别家碰撞贴合（贴合=不可见）
			var visible := false
			var t2: float = f0 + 0.5
			while t2 < f1:
				var sp2: Vector2
				var ap: Vector2
				if out.x != 0.0:
					sp2 = Vector2(face_pos + out.x * 0.9, t2)
					ap = Vector2(face_pos + out.x * 0.45, t2)
				else:
					sp2 = Vector2(t2, face_pos + out.y * 0.9)
					ap = Vector2(t2, face_pos + out.y * 0.45)
				var abut := false
				for col in _cols:
					if col["y1"] < 1.0:
						continue
					if _pt_in_rect(ap.x, ap.y, col["rect"]):
						abut = true
						break
				if not abut:
					var ri := _cell_idx(sp2.x, sp2.y)
					if ri >= 0 and _reach[ri] == 1:
						visible = true
						break
				t2 += 0.5
			if not visible:
				continue
			# 是否已有套件件贴此面
			var dressed := false
			for kp in _kit_pts:
				var d_plane: float
				var along: float
				if out.x != 0.0:
					d_plane = absf(kp.x - face_pos)
					along = kp.z
				else:
					d_plane = absf(kp.z - face_pos)
					along = kp.x
				if d_plane < 0.6 and along > f0 - 0.5 and along < f1 + 0.5:
					dressed = true
					break
			if not dressed:
				undressed += 1
				var dir_name := "+X" if out.x > 0 else ("-X" if out.x < 0 else ("+Z" if out.y > 0 else "-Z"))
				print("C. 缺立面 %s 面%s 跨度[%.1f..%.1f] 面位%.1f" % [b["id"], dir_name, f0, f1, face_pos])
	print("C. 缺立面墙面 %d" % undressed)

	print("AUDIT_MAP done")
	quit()
