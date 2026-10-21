# probe_hand_axes.py — print world-space axes of hand bones after rig transform + pose
# usage: blender -b --python probe_hand_axes.py -- <arms_glb> <params.json>
import bpy, sys, math, json
from mathutils import Vector, Euler, Matrix

argv = sys.argv[sys.argv.index("--")+1:]
arms_glb, params_path = argv[0], argv[1]
P = json.load(open(params_path, encoding="utf-8"))

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=arms_glb)
for ob in list(bpy.data.objects):
    if ob.type == "MESH" and len(ob.data.vertices) < 100:
        bpy.data.objects.remove(ob, do_unlink=True)
arm_ob = next(ob for ob in bpy.data.objects if ob.type == 'ARMATURE')
bpy.context.view_layer.update()
M0 = arm_ob.matrix_world.copy()
desired = (Matrix.Translation(Vector(P["rig_loc"]))
           @ Matrix.Rotation(math.radians(P["rig_rot"][2]), 4, 'Z')
           @ Matrix.Rotation(math.radians(P["rig_rot"][1]), 4, 'Y')
           @ Matrix.Rotation(math.radians(P["rig_rot"][0]), 4, 'X')
           @ Matrix.Scale(P["rig_scale"], 4)
           @ M0)
arm_ob.matrix_world = desired
bpy.context.view_layer.update()

def pb(prefix):
    for b in arm_ob.pose.bones:
        if b.name.startswith(prefix):
            return b

for name in ("hand.R", "hand.L", "f_index.01.R", "f_middle.01.R", "thumb.01.R", "palm.R", "forearm.R"):
    b = pb(name)
    if b is None:
        print("AXES", name, "NOT FOUND")
        continue
    mw = arm_ob.matrix_world @ b.matrix
    x = (mw.to_3x3() @ Vector((1, 0, 0))).normalized()
    y = (mw.to_3x3() @ Vector((0, 1, 0))).normalized()
    z = (mw.to_3x3() @ Vector((0, 0, 1))).normalized()
    print("AXES %s head=%s X=%s Y=%s Z=%s" % (
        name,
        tuple(round(v, 3) for v in (arm_ob.matrix_world @ b.head)),
        tuple(round(v, 3) for v in x),
        tuple(round(v, 3) for v in y),
        tuple(round(v, 3) for v in z)))
