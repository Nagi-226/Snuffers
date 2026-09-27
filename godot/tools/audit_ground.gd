extends SceneTree
## 地面覆盖审计工具（2026-09-27 地面虚空大排查）
## 用法: godot --headless --path . --script tools/audit_ground.gd
## 在铺装包络内网格采样，凡不落任何铺装/建筑/围挡面 = 露泥地接缝 → 打印成行段报告

func _pt_in_rect(px: float, pz: float, r: Array) -> bool:
	return px > r[0] and px < r[2] and pz > r[1] and pz < r[3]


func _init() -> void:
	var L: GDScript = load("res://scripts/levels/street_layout_test.gd")
	var s: Dictionary = L.STREET
	var c: Dictionary = L.CROSS
	var se: Dictionary = L.SOUTH_EXT

	# —— 铺装面（与 builder._build_ground / ZoneGround 保持一致）——
	var paved: Array = [
		[-s["half_width"], s["z_min"], s["half_width"], s["z_max"]],     # 沥青主街
		[-s["kerb"], s["z_min"], -s["half_width"], s["z_max"]],          # 西侧人行道
		[s["half_width"], s["z_min"], s["kerb"], s["z_max"]],            # 东侧人行道
		[c["x_min"], c["z_min"], c["x_max"], c["z_max"]],                # 横街沥青
		[c["x_min"], c["z_max"], -s["kerb"], c["walk_south_z"]],         # 横街南人行道西段
		[s["kerb"], c["z_max"], c["x_max"], c["walk_south_z"]],          # 横街南人行道东段
		[-s["half_width"], se["z_min"], s["half_width"], se["z_max"]],   # 南延沥青
		[-s["kerb"], se["z_min"], -s["half_width"], se["z_max"]],        # 南延西人行道
		[s["half_width"], se["z_min"], s["kerb"], se["z_max"]],          # 南延东人行道
	]
	for a in L.ALLEYS:
		paved.append(a["rect"])
	for z in L.BACKFILL_ZONES:
		paved.append(z.get("ground_rect", z["rect"]))

	# —— 建筑 footprint（楼底下不需要铺装）——
	var blds: Array = []
	for b in L.BUILDINGS:
		blds.append([b["x"] - b["w"] * 0.5, b["z"] - b["d"] * 0.5,
			b["x"] + b["w"] * 0.5, b["z"] + b["d"] * 0.5])
	for g in L.BARRIERS:
		blds.append([g["x"] - g["w"] * 0.5, g["z"] - g["d"] * 0.5,
			g["x"] + g["w"] * 0.5, g["z"] + g["d"] * 0.5])

	# —— 网格采样（铺装包络：|x|<=44, z -162..106；包络外由 OuterGround 兜底）——
	var step := 0.5
	var bad_cells := 0
	var prev_sig := ""
	var run_start_z := 0.0
	var z: float = -162.0
	while z <= 106.0:
		var runs: Array = []
		var x: float = -44.0
		var run_x := -999.0
		while x <= 44.0:
			var covered := false
			for r in paved:
				if _pt_in_rect(x + step * 0.5, z + step * 0.5, r):
					covered = true
					break
			if not covered:
				for r in blds:
					if _pt_in_rect(x + step * 0.5, z + step * 0.5, r):
						covered = true
						break
			if not covered:
				bad_cells += 1
				if run_x < -900.0:
					run_x = x
			else:
				if run_x > -900.0:
					runs.append([run_x, x])
					run_x = -999.0
			x += step
		if run_x > -900.0:
			runs.append([run_x, 44.0])
		var sig := str(runs)
		if sig != prev_sig:
			if prev_sig != "" and prev_sig != "[]":
				print("  z %.1f..%.1f 露泥段: %s" % [run_start_z, z, prev_sig])
			prev_sig = sig
			run_start_z = z
		z += step
	if prev_sig != "" and prev_sig != "[]":
		print("  z %.1f..%.1f 露泥段: %s" % [run_start_z, z, prev_sig])
	print("AUDIT done: 露泥单元 %d 个（每格 %.1f×%.1f m）" % [bad_cells, step, step])
	quit()
