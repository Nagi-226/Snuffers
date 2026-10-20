"""寄生体 B 方案拼接手术：原模型上半身（保真度高）+ 文生 3D 新模型下半身（完整腿靴）。

流程：
1. 导入原模型（大腿处截断的半身模）与新全身模，两者均为归一化 1m 高；
2. 原模型在「截断面略上」处水平剖切，保留平面以上（去掉 AI 截断的锯齿边）；
3. 新模型做宽度匹配：在腿部自上而下找「横截面 X 向宽度 ≈ 原模型剖切面宽度」的高度，
   在该高度剖切保留下半，再整体缩放使剖切面宽度精确一致，平移到原模型剖切面下方；
4. 两网格 join（各自材质槽保留），导出 GLB。

用法：
  blender --background --factory-startup --python graft_host_body.py -- <upper_glb> <full_glb> <out_glb>
"""
import bpy, sys, json, bmesh
import mathutils

argv = sys.argv[sys.argv.index("--") + 1:]
upper_path, full_path, out_path = argv[0], argv[1], argv[2]

CUT_MARGIN = 0.012   # 原模型剖切面上移量（去掉截断锯齿边）
BAND = 0.02          # 横截面宽度采样带半宽

bpy.ops.wm.read_factory_settings(use_empty=True)


def import_glb(path, prefix):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    news = [o for o in bpy.data.objects if o not in before]
    meshes = [o for o in news if o.type == "MESH"]
    assert meshes, "no mesh in %s" % path
    for o in meshes:
        o.name = "%s_%s" % (prefix, o.name)
    return meshes


def world_bbox(objs):
    mins = mathutils.Vector((1e9,) * 3)
    maxs = mathutils.Vector((-1e9,) * 3)
    for o in objs:
        for c in o.bound_box:
            w = o.matrix_world @ mathutils.Vector(c)
            mins = mathutils.Vector(map(min, mins, w))
            maxs = mathutils.Vector(map(max, maxs, w))
    return mins, maxs


def section_width_x(obj, z_plane):
    """z_plane 附近 ±BAND 带内顶点的世界 X 跨度。"""
    inv = obj.matrix_world.inverted()
    xs = []
    for v in obj.data.vertices:
        w = obj.matrix_world @ v.co
        if abs(w.z - z_plane) <= BAND:
            xs.append(w.x)
    if len(xs) < 4:
        return None
    return max(xs) - min(xs)


def bisect_keep(obj, z_plane, keep_above):
    """水平剖切：删除平面另一侧的面。"""
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    bm = bmesh.from_edit_mesh(obj.data)
    # 用 bisect 切开后按面心高度删除
    geom = list(bm.verts) + list(bm.edges) + list(bm.faces)
    bmesh.ops.bisect_plane(bm, geom=geom, dist=0.0001,
                           plane_co=(0, 0, z_plane), plane_no=(0, 0, 1),
                           clear_inner=False, clear_outer=False)
    bmesh.update_edit_mesh(obj.data)
    bm = bmesh.from_edit_mesh(obj.data)
    doomed = []
    for f in bm.faces:
        cz = f.calc_center_median().z
        if keep_above and cz < z_plane:
            doomed.append(f)
        if not keep_above and cz > z_plane:
            doomed.append(f)
    bmesh.ops.delete(bm, geom=doomed, context="FACES")
    bmesh.update_edit_mesh(obj.data)
    bpy.ops.object.mode_set(mode="OBJECT")


upper_objs = import_glb(upper_path, "UP")
full_objs = import_glb(full_path, "NEW")
assert len(upper_objs) == 1 and len(full_objs) == 1, "expect single-mesh GLBs"
up, new = upper_objs[0], full_objs[0]

# 应用变换，统一到世界空间操作（两者都应是 identity，防御性处理）
for o in (up, new):
    bpy.context.view_layer.objects.active = o
    o.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    o.select_set(False)

up_min, up_max = world_bbox([up])
new_min, new_max = world_bbox([new])
report = {"up_bbox": [list(up_min), list(up_max)], "new_bbox": [list(new_min), list(new_max)]}

# 1) 原模型剖切面：最低点上方 CUT_MARGIN
z_cut_up = up_min.z + CUT_MARGIN
w_up = section_width_x(up, z_cut_up)
assert w_up is not None, "upper section sampling failed"
report["z_cut_up"] = z_cut_up
report["w_up"] = w_up

# 2) 新模型：限定腿部合理区间（膝→髋，归一化 0.30H..0.58H）内找
#    横截面宽度最接近 w_up 的高度；全局搜索会被靴筒宽度带偏到脚踝。
h_new = new_max.z - new_min.z
z_lo = new_min.z + 0.30 * h_new
z_hi = new_min.z + 0.58 * h_new
best_z, best_w, best_err = None, None, 1e9
z = z_lo
while z <= z_hi:
    w = section_width_x(new, z)
    if w is not None:
        err = abs(w - w_up)
        if err < best_err:
            best_z, best_w, best_err = z, w, err
    z += 0.005
assert best_z is not None, "no matching section on new model"
report["z_cut_new"] = best_z
report["w_new_raw"] = best_w

# 3) 剖切
bisect_keep(up, z_cut_up, keep_above=True)
bisect_keep(new, best_z, keep_above=False)

# 4) 新模型下半身缩放对齐：X/Y 按宽度比缩放（Z 同步保持比例），平移到剖切面下方
scale = w_up / best_w
cx_new = (world_bbox([new])[0].x + world_bbox([new])[1].x) / 2
cy_new = (world_bbox([new])[0].y + world_bbox([new])[1].y) / 2
cx_up = (world_bbox([up])[0].x + world_bbox([up])[1].x) / 2
cy_up = (world_bbox([up])[0].y + world_bbox([up])[1].y) / 2
for v in new.data.vertices:
    v.co.x = (v.co.x - cx_new) * scale + cx_up
    v.co.y = (v.co.y - cy_new) * scale + cy_up
    v.co.z = (v.co.z - best_z) * scale + z_cut_up
report["scale"] = scale

# 4.5) 悬空件清理（缩放对齐后）：新模 AI 网格碎片化严重（loose parts 几十片，
# 腿本体也是碎壳），不能按大小/质心取舍；用「落地洪水」——从贴地碎块（靴底）
# 出发，按包围盒膨胀 2cm 逐层邻接生长，腿/裤/靴自然连成一片；
# 被切断的手/枪套与腿柱之间有可见空气间隙，进不了洪水。
FLOOD_DELTA = 0.02
bpy.ops.object.select_all(action="DESELECT")
new.select_set(True)
bpy.context.view_layer.objects.active = new
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.mesh.separate(type="LOOSE")
bpy.ops.object.mode_set(mode="OBJECT")
parts = [o for o in bpy.context.selected_objects if o.type == "MESH" and o != up]
assert parts, "loose-part separation produced nothing"


def _bbox(o):
    xs = [v.co.x for v in o.data.vertices]
    ys = [v.co.y for v in o.data.vertices]
    zs = [v.co.z for v in o.data.vertices]
    return (min(xs), min(ys), min(zs), max(xs), max(ys), max(zs))


def _inter(a, b, d):
    return not (a[3] + d < b[0] or b[3] + d < a[0]
                or a[4] + d < b[1] or b[4] + d < a[1]
                or a[5] + d < b[2] or b[5] + d < a[2])


boxes = {o: _bbox(o) for o in parts}
# 种子：最低点 6cm 内的碎块（靴底）。阈值动态取（此时坐标尚未归一化）。
z_floor = min(b[2] for b in boxes.values())
kept = [o for o in parts if boxes[o][2] <= z_floor + 0.06]
assert kept, "no ground-touching seed parts"
changed = True
while changed:
    changed = False
    for o in parts:
        if o in kept:
            continue
        if any(_inter(boxes[o], boxes[s], FLOOD_DELTA) for s in kept):
            kept.append(o)
            changed = True
dropped = [(o.name, len(o.data.vertices)) for o in parts if o not in kept]
report["flood_seed"] = len([o for o in parts if boxes[o][2] <= z_floor + 0.06])
report["dropped_parts"] = dropped
report["kept_count"] = len(kept)
for name, _n in dropped:
    bpy.data.objects.remove(bpy.data.objects[name], do_unlink=True)
# 幸存碎块合回单一对象
bpy.ops.object.select_all(action="DESELECT")
for o in kept:
    o.select_set(True)
bpy.context.view_layer.objects.active = kept[0]
if len(kept) > 1:
    bpy.ops.object.join()
new = kept[0]

# 5) join：up 为主（保留两者材质槽）
bpy.ops.object.select_all(action="DESELECT")
up.select_set(True)
new.select_set(True)
bpy.context.view_layer.objects.active = up
bpy.ops.object.join()
up.name = "host_parasite_grafted"

final_min, final_max = world_bbox([up])
# 6) 归一化：拼接后总高 >1m（半身模拉长到 1m + 腿），统一缩回 1m 高、
#    X/Y 居中、脚底 -0.5——与入库 GLB 的既有约定一致（游戏侧 ×1.75 不变）。
final_h = final_max.z - final_min.z
norm = 1.0 / final_h
cx_f = (final_min.x + final_max.x) / 2
cy_f = (final_min.y + final_max.y) / 2
for v in up.data.vertices:
    v.co.x = (v.co.x - cx_f) * norm
    v.co.y = (v.co.y - cy_f) * norm
    v.co.z = (v.co.z - final_min.z) * norm - 0.5
report["final_raw_h"] = final_h
report["norm_scale"] = norm
report["final_bbox"] = [list(final_min), list(final_max)]
report["materials"] = [m.name if m else None for m in up.data.materials]

bpy.ops.export_scene.gltf(filepath=out_path, export_format="GLB", export_yup=True,
                          export_apply=False, export_animations=False)
print("GRAFT " + json.dumps(report))
