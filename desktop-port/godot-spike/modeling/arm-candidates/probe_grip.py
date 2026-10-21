# probe_grip.py — print sub-object bboxes of weapon proxy in blender space (after weapon_scale)
# usage: blender -b --python probe_grip.py -- <weapon_proxy> <weapon_scale>
import bpy, sys, json
from mathutils import Vector

argv = sys.argv[sys.argv.index("--")+1:]
proxy, ws = argv[0], float(argv[1])

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=proxy)
for ob in bpy.data.objects:
    if ob.type == 'MESH':
        ob.scale = (ws, ws, ws)
bpy.context.view_layer.update()
dg = bpy.context.evaluated_depsgraph_get()
for ob in bpy.data.objects:
    if ob.type != 'MESH':
        continue
    ev = ob.evaluated_get(dg)
    me = ev.to_mesh()
    mw = ev.matrix_world
    pts = [mw @ v.co for v in me.vertices]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    print("BBOX %s lo=%s hi=%s center=%s n=%d" % (
        ob.name,
        tuple(round(v, 4) for v in lo),
        tuple(round(v, 4) for v in hi),
        tuple(round(v, 4) for v in ((lo + hi) / 2)),
        len(pts)))
    ev.to_mesh_clear()
