# probe_palm_axis.py — apply full pose (rig transform + IK + bones) then report
# which hand.R / hand.L local axis points along given world reference dirs.
# usage: blender -b --python probe_palm_axis.py -- <arms_glb> <params.json>
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
mesh = max((ob for ob in bpy.data.objects if ob.type == 'MESH' and ob.find_armature() == arm_ob),
           key=lambda o: len(o.data.vertices))
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

vg = {g.index: g.name for g in mesh.vertex_groups}

def centroid(match):
    dg = bpy.context.evaluated_depsgraph_get()
    ev = mesh.evaluated_get(dg)
    me = ev.to_mesh()
    mw = ev.matrix_world
    acc = Vector(); n = 0
    for v in me.vertices:
        for g in v.groups:
            if vg.get(g.group, "").startswith(match) and g.weight > 0.5:
                acc += mw @ v.co; n += 1
                break
    ev.to_mesh_clear()
    return acc / n if n else None

for prefix, ang in P.get("pre_bones", {}).items():
    b = pb(prefix)
    if b:
        b.rotation_mode = 'XYZ'
        b.rotation_euler = Euler(tuple(math.radians(a) for a in ang), 'XYZ')
bpy.context.view_layer.update()

for chain in P.get("ik", []):
    bones = [pb(nm) for nm in chain["bones"]]
    target = Vector(chain["target"]); meas = chain["measure"]
    step = math.radians(chain.get("start_step_deg", 4.0)); dist = 1e9
    for it in range(chain.get("iters", 90)):
        dist = (centroid(meas) - target).length
        if dist < chain.get("tol", 0.004):
            break
        improved = False
        for b in bones:
            b.rotation_mode = 'XYZ'
            for ax in range(3):
                base_e = list(b.rotation_euler); best_d = dist; best = 0.0
                for sgn in (1, -1):
                    e = list(base_e); e[ax] += sgn * step
                    b.rotation_euler = Euler(e, 'XYZ')
                    bpy.context.view_layer.update()
                    d = (centroid(meas) - target).length
                    if d < best_d - 1e-5:
                        best_d = d; best = sgn * step
                b.rotation_euler = Euler(base_e, 'XYZ')
                if best != 0.0:
                    e = list(base_e); e[ax] += best
                    b.rotation_euler = Euler(e, 'XYZ')
                    bpy.context.view_layer.update()
                    dist = best_d; improved = True
        if not improved:
            step *= 0.5
            if step < math.radians(0.15):
                break

for prefix, ang in P.get("bones", {}).items():
    b = pb(prefix)
    if b:
        b.rotation_mode = 'XYZ'
        b.rotation_euler = Euler(tuple(math.radians(a) for a in ang), 'XYZ')
bpy.context.view_layer.update()

for name in ("hand.R", "hand.L"):
    b = pb(name)
    mw = arm_ob.matrix_world @ b.matrix
    R = mw.to_3x3()
    print("PALM %s localX=%s localY=%s localZ=%s" % (
        name,
        tuple(round(v, 3) for v in (R @ Vector((1, 0, 0))).normalized()),
        tuple(round(v, 3) for v in (R @ Vector((0, 1, 0))).normalized()),
        tuple(round(v, 3) for v in (R @ Vector((0, 0, 1))).normalized())))
