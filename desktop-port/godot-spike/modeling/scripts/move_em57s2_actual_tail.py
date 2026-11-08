"""Move the original EM-57S-2 tail surface, UVs and materials without adding geometry."""
import bpy
import bmesh
import mathutils
import os
import sys

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if len(argv) == 3:
    CAP_PATHS = [os.path.abspath(argv[0])]
    LAUNCHER, SMG_ADS = map(os.path.abspath, argv[1:3])
elif len(argv) == 5:
    CAP_PATHS = list(map(os.path.abspath, argv[:3]))
    LAUNCHER, SMG_ADS = map(os.path.abspath, argv[3:])
else:
    raise SystemExit("usage: move_em57s2_actual_tail.py <tail11> [<tail09> <tail10> <tail11>] <launcher> <smg_ads>")
OUT = LAUNCHER

bpy.ops.wm.read_factory_settings(use_empty=True)
cap = None
for index, path in enumerate(CAP_PATHS):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    part = next(obj for obj in set(bpy.data.objects) - before if obj.type == "MESH")
    if cap is None:
        cap = part
        continue
    bpy.ops.object.select_all(action="DESELECT")
    cap.select_set(True)
    part.select_set(True)
    bpy.context.view_layer.objects.active = cap
    bpy.ops.object.join()
cap_mesh = cap.data
points = [cap.matrix_world @ vertex.co for vertex in cap_mesh.vertices]
lo = mathutils.Vector(tuple(min(point[i] for point in points) for i in range(3)))
hi = mathutils.Vector(tuple(max(point[i] for point in points) for i in range(3)))
center = (lo + hi) * 0.5
scale = 0.115 / max(hi.x - lo.x, hi.z - lo.z)
for vertex in cap_mesh.vertices:
    point = cap.matrix_world @ vertex.co
    vertex.co = ((point.x - center.x) * scale, (point.y - hi.y) * scale + 0.08, (point.z - center.z) * scale + 0.19)
cap.matrix_world = mathutils.Matrix.Identity(4)
cap_mesh.update()
print("ORIGINAL_TAIL_FACES", len(cap_mesh.polygons), flush=True)

bpy.ops.import_scene.gltf(filepath=LAUNCHER)
target = next(obj for obj in bpy.context.scene.objects if obj.type == "MESH" and obj != cap)
bm = bmesh.new()
bm.from_mesh(target.data)
removed = [face for face in bm.faces if any(v.co.y < 0.12 and v.co.z > 0.10 and abs(v.co.x) < 0.07 for v in face.verts)]
bmesh.ops.delete(bm, geom=removed, context="FACES")
bm.to_mesh(target.data)
bm.free()
target.data.update()
print("OLD_REAR_FACES_REMOVED", len(removed), flush=True)
bpy.ops.object.select_all(action="DESELECT")
target.select_set(True)
cap.select_set(True)
bpy.context.view_layer.objects.active = target
bpy.ops.object.join()
target.data.calc_loop_triangles()
print("FINAL_TRIANGLES", len(target.data.loop_triangles), flush=True)
bpy.ops.object.select_all(action="DESELECT")
target.select_set(True)
bpy.context.view_layer.objects.active = target
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True, export_yup=True, export_apply=True, export_animations=False)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SMG_ADS)
smg = next(obj for obj in bpy.context.scene.objects if obj.type == "MESH")
bm = bmesh.new()
bm.from_mesh(smg.data)
bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.calc_center_median().y > 0.374 and abs(f.calc_center_median().z) < 0.04], context="FACES")
bm.to_mesh(smg.data)
bm.free()
smg.data.update()
bpy.ops.object.select_all(action="DESELECT")
smg.select_set(True)
bpy.context.view_layer.objects.active = smg
bpy.ops.export_scene.gltf(filepath=SMG_ADS, export_format="GLB", use_selection=True, export_yup=True, export_apply=True, export_animations=False)
print("SMG_TAIL_REMOVED_FOR_ADS", flush=True)
