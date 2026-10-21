# iter_palm_axis.py — apply rig+IK, then render hand.R with 6 palm_axis candidates
# in ONE session (apply aim -> render -> restore), front+side each.
# usage: blender -b --python iter_palm_axis.py -- <arms_glb> <weapon_proxy> <out_prefix> <params.json>
import bpy, sys, math, json, os
from mathutils import Vector, Euler, Matrix

argv = sys.argv[sys.argv.index("--")+1:]
arms_glb, weapon_proxy, out_prefix, params_path = argv[0], argv[1], argv[2], argv[3]
if not os.path.isabs(out_prefix):
    out_prefix = os.path.join(os.path.dirname(os.path.abspath(__file__)), out_prefix)
P = json.load(open(params_path, encoding="utf-8"))

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=arms_glb)
for ob in list(bpy.data.objects):
    if ob.type == "MESH" and len(ob.data.vertices) < 100:
        bpy.data.objects.remove(ob, do_unlink=True)
bpy.ops.import_scene.gltf(filepath=weapon_proxy)
ws = P.get("weapon_scale", 1.0)
if ws != 1.0:
    for ob in bpy.data.objects:
        if ob.type == 'MESH' and ob.find_armature() is None:
            ob.scale = (ws, ws, ws)
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

# finger curls (bones dict, excluding hand.* — hands handled by aim)
for prefix, ang in P.get("bones", {}).items():
    if prefix.startswith("hand."):
        continue
    b = pb(prefix)
    if b:
        b.rotation_mode = 'XYZ'
        b.rotation_euler = Euler(tuple(math.radians(a) for a in ang), 'XYZ')
bpy.context.view_layer.update()

# ---- render setup ----
sc = bpy.context.scene
try: sc.render.engine = 'BLENDER_EEVEE'
except TypeError: sc.render.engine = 'BLENDER_EEVEE_NEXT'
sc.render.resolution_x = 800; sc.render.resolution_y = 512
sc.world = bpy.data.worlds.new("w"); sc.world.use_nodes = True
sc.world.node_tree.nodes["Background"].inputs[0].default_value = (0.12, 0.12, 0.15, 1)
for i, rot in enumerate([(math.radians(55), math.radians(5), math.radians(25)),
                          (math.radians(40), 0, math.radians(-140))]):
    ld = bpy.data.lights.new("k%d" % i, 'SUN'); ld.energy = 2.0
    lo = bpy.data.objects.new("k%d" % i, ld); lo.rotation_euler = rot
    sc.collection.objects.link(lo)
cam_data = bpy.data.cameras.new("cam"); cam = bpy.data.objects.new("cam", cam_data)
sc.collection.objects.link(cam); sc.camera = cam
views = {
    "side": (Vector((0.75, -0.35, 0.05)), Vector((0, -0.08, -0.06)), 50),
    "front": (Vector((0.02, 0.55, 0.02)), Vector((0, -0.05, -0.06)), 50),
    "top": (Vector((0.02, -0.05, 0.55)), Vector((0, -0.06, -0.07)), 50),
}

def _aim_basis(f, p):
    y = f.normalized()
    z = (p - y * p.dot(y)).normalized()
    x = y.cross(z)
    m = Matrix.Identity(3)
    m.col[0], m.col[1], m.col[2] = x, y, z
    return m

def apply_aim(name, f_tgt, p_tgt, p_axis):
    b = pb(name)
    R = (arm_ob.matrix_world @ b.matrix).to_3x3()
    f_cur = R @ Vector((0, 1, 0))
    p_cur = R @ Vector(p_axis)
    C = (_aim_basis(Vector(f_tgt), Vector(p_tgt)) @ _aim_basis(f_cur, p_cur).inverted()).to_4x4()
    new_world = C @ (arm_ob.matrix_world @ b.matrix)
    b.matrix = arm_ob.matrix_world.inverted() @ new_world
    bpy.context.view_layer.update()

CANDS = [("+X", [1, 0, 0]), ("-X", [-1, 0, 0]), ("+Y", [0, 1, 0]),
         ("-Y", [0, -1, 0]), ("+Z", [0, 0, 1]), ("-Z", [0, 0, -1])]

aims = P["hand_aim"]
saved = {}
for nm in aims:
    b = pb(nm)
    saved[nm] = (arm_ob.matrix_world @ b.matrix).copy()

for tag, pax in CANDS:
    for nm, a in aims.items():
        b = pb(nm)
        b.matrix = arm_ob.matrix_world.inverted() @ saved[nm]
    bpy.context.view_layer.update()
    for nm, a in aims.items():
        apply_aim(nm, a["fingers"], a["palm"], pax)
    for vname, (loc2, look, lens) in views.items():
        cam.location = loc2
        cam.rotation_euler = (look - loc2).to_track_quat('-Z', 'Y').to_euler()
        cam_data.lens = lens
        sc.render.filepath = "%s_%s_%s.png" % (out_prefix, tag.replace("+", "p").replace("-", "m"), vname)
        bpy.ops.render.render(write_still=True)
    print("CAND_DONE", tag)
print("ITER_OK")
