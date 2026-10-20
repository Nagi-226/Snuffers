"""从完整步枪 GLB 提取"开孔瞄具"独立件（仅 em68a_optic，已做镜孔手术）。

用途：常规视角用完整 GLB（瞄具完好），开镜瞬间把瞄具 MeshInstance3D 的
mesh 切换为本文件里的开孔版，松开右键切回——实现完整/透视双状态无缝切换，
而不需要第二份 50MB 整枪 GLB。

用法：
  blender --background --factory-startup --python extract_optic_bored.py -- <src_glb> <dst_glb>
"""
import bpy, sys, json
import mathutils

argv = sys.argv[sys.argv.index("--") + 1:]
src, dst = argv[0], argv[1]

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)

optic = bpy.data.objects.get("em68a_optic")
assert optic is not None, "em68a_optic not found"

# ---- 镜孔手术（与 open_optic_lens.py v4 同算法，保持双件几何一致）----
bb = [mathutils.Vector(c) for c in optic.bound_box]
min_x = min(v.x for v in bb); max_x = max(v.x for v in bb)
min_z = min(v.z for v in bb); max_z = max(v.z for v in bb)
cx = (min_x + max_x) / 2
span_x = max_x - min_x

mesh = optic.data

est = []
for poly in mesh.polygons:
    if abs(poly.normal.y) < 0.8:
        continue
    c = poly.center
    if abs(c.x - cx) > 0.3 * span_x:
        continue
    est.append(c)
assert len(est) > 50, "axis-perpendicular faces too few to estimate bore: %d" % len(est)
z0 = sum(c.z for c in est) / len(est)
r = max(abs(c.x - cx) for c in est) * 1.15

sel = []
for poly in mesh.polygons:
    c = poly.center
    dx = c.x - cx
    dz = c.z - z0
    if dx * dx + dz * dz < r * r:
        sel.append(poly.index)

report = {"candidate_faces": len(sel), "total_faces": len(mesh.polygons)}
assert len(sel) < len(mesh.polygons) * 0.45, "too many candidate faces: %d" % len(sel)
assert len(sel) > 0, "no candidate faces found"

bpy.context.view_layer.objects.active = optic
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="DESELECT")
bpy.ops.object.mode_set(mode="OBJECT")
for idx in sel:
    mesh.polygons[idx].select = True
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.delete(type="FACE")
bpy.ops.object.mode_set(mode="OBJECT")

report["faces_after"] = len(mesh.polygons)
report["deleted"] = report["total_faces"] - report["faces_after"]

# ---- 只保留瞄具对象，其余删除 ----
for obj in list(bpy.data.objects):
    if obj.name != "em68a_optic":
        bpy.data.objects.remove(obj, do_unlink=True)

bpy.ops.export_scene.gltf(filepath=dst, export_format="GLB", export_yup=True,
                          export_apply=False, export_animations=False)

print("OPTICBORED " + json.dumps(report))
