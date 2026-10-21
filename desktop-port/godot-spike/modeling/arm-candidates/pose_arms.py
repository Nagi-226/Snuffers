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
# scale weapon proxy into display (mount) space if requested
ws = P.get("weapon_scale", 1.0)
if ws != 1.0:
    for ob in bpy.data.objects:
        if ob.type == 'MESH' and ob.find_armature() is None:
            ob.scale = (ws, ws, ws)

arm_ob = next(ob for ob in bpy.data.objects if ob.type == 'ARMATURE')
mesh = max((ob for ob in bpy.data.objects if ob.type == 'MESH' and ob.find_armature() == arm_ob),
           key=lambda o: len(o.data.vertices))

# rig object transform (compose on original world matrix to survive FBX parent chain)
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

def pb(name_prefix):
    for b in arm_ob.pose.bones:
        if b.name.startswith(name_prefix):
            return b
    return None

vg = {g.index: g.name for g in mesh.vertex_groups}

# ---- slim: rest-pose 网格编辑，把指定骨骼区域沿自身 PCA 主轴径向收细 ----
# JSON: "slim": {"upper_arm": {"strength": 0.55, "taper": 0.35}}
# strength = 肩端最大收缩比例；taper = 肘端保留的收缩比例（线性过渡）。
def _group_index(prefix_name):
    for g in mesh.vertex_groups:
        if g.name.startswith(prefix_name):
            return g.index
    return None

def _rest_centroid(prefix_name):
    gi = _group_index(prefix_name)
    if gi is None:
        return None
    mw = mesh.matrix_world
    acc = Vector(); n = 0
    for v in mesh.data.vertices:
        for g in v.groups:
            if g.group == gi and g.weight > 0.5:
                acc += mw @ v.co; n += 1
                break
    return acc / n if n else None

def apply_slim():
    slim = P.get("slim")
    if not slim:
        return
    import numpy as np
    mw = mesh.matrix_world
    mw_inv = mw.inverted()
    for prefix, cfg in slim.items():
        strength = cfg.get("strength", 0.5)
        taper = cfg.get("taper", 0.35)
        for side in ("R", "L"):
            gi = _group_index("%s.%s" % (prefix, side))
            if gi is None:
                print("SLIM MISS %s.%s" % (prefix, side)); continue
            pts = []
            for v in mesh.data.vertices:
                w = 0.0
                for g in v.groups:
                    if g.group == gi:
                        w = g.weight
                        break
                if w > 0.05:
                    pts.append((v.index, w, mw @ v.co))
            if len(pts) < 10:
                continue
            elbow_c = _rest_centroid("forearm." + side)
            arr = np.array([[p[2].x, p[2].y, p[2].z] for p in pts])
            c = arr.mean(axis=0)
            cov = np.cov((arr - c).T)
            vals, vecs = np.linalg.eigh(cov)
            axis = Vector(vecs[:, int(np.argmax(vals))]).normalized()
            if elbow_c is not None and (elbow_c - Vector(c)).dot(axis) < 0:
                axis = -axis
            cv = Vector(c)
            ts = [(p[2] - cv).dot(axis) for p in pts]
            tmin, tmax = min(ts), max(ts)
            for (vi, w, pw), tt in zip(pts, ts):
                tn = (tt - tmin) / max(tmax - tmin, 1e-9)
                s = min(strength * w * (taper + (1.0 - taper) * (1.0 - tn)), 0.7)
                radial = (pw - cv) - axis * tt
                newp = cv + axis * tt + radial * (1.0 - s)
                mesh.data.vertices[vi].co = mw_inv @ newp
            print("SLIM %s.%s n=%d strength=%.2f taper=%.2f" % (prefix, side, len(pts), strength, taper))

apply_slim()

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

# ---- pre-FK (initial pose guess before IK, helps CCD avoid local minima) ----
for prefix, ang in P.get("pre_bones", {}).items():
    b = pb(prefix)
    if not b:
        print("MISS PRE BONE", prefix); continue
    b.rotation_mode = 'XYZ'
    b.rotation_euler = Euler(tuple(math.radians(a) for a in ang), 'XYZ')
bpy.context.view_layer.update()

# ---- auto IK (numeric CCD using mesh centroid feedback) ----
for chain in P.get("ik", []):
    bones = [pb(nm) for nm in chain["bones"]]
    target = Vector(chain["target"])
    meas = chain["measure"]
    step = math.radians(chain.get("start_step_deg", 4.0))
    dist = 1e9
    for it in range(chain.get("iters", 90)):
        cur = centroid(meas)
        dist = (cur - target).length
        if dist < chain.get("tol", 0.004):
            break
        improved = False
        for b in bones:
            b.rotation_mode = 'XYZ'
            for ax in range(3):
                base_e = list(b.rotation_euler)
                best_d = dist; best = 0.0
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
                    dist = best_d
                    improved = True
        if not improved:
            step *= 0.5
            if step < math.radians(0.15):
                break
    print("IK %-10s final_dist %.4f" % (meas, dist))

# ---- hand_aim: world-space hand orientation (palm/finger direction semantics) ----
# JSON: "hand_aim": {"hand.R": {"fingers": [x,y,z], "palm": [x,y,z], "palm_axis": [0,0,1]}, ...}
# fingers = 世界空间中手指（掌骨）指向；palm = 掌心朝向。
# palm_axis = 掌心法向对应的骨骼局部轴（默认 [0,0,1]，若实测掌心偏 90° 试 [±1,0,0]）。
def _aim_basis(f, p):
    y = f.normalized()
    z = (p - y * p.dot(y)).normalized()
    x = y.cross(z)
    m = Matrix.Identity(3)
    m.col[0], m.col[1], m.col[2] = x, y, z
    return m

for name, aim in P.get("hand_aim", {}).items():
    b = pb(name)
    if not b:
        print("MISS AIM BONE", name); continue
    f_tgt = Vector(aim["fingers"])
    p_tgt = Vector(aim["palm"])
    p_axis = Vector(aim.get("palm_axis", [0, 0, 1]))
    f_axis = Vector(aim.get("finger_axis", [0, 1, 0]))
    bpy.context.view_layer.update()
    R = (arm_ob.matrix_world @ b.matrix).to_3x3()
    f_cur = R @ f_axis
    p_cur = R @ p_axis
    M_cur = _aim_basis(f_cur, p_cur)
    M_des = _aim_basis(f_tgt, p_tgt)
    C = (M_des @ M_cur.inverted()).to_4x4()
    new_world = C @ (arm_ob.matrix_world @ b.matrix)
    b.matrix = arm_ob.matrix_world.inverted() @ new_world
    bpy.context.view_layer.update()
    print("AIM %-8s fingers->%s palm->%s paxis=%s" % (name, aim["fingers"], aim["palm"], list(p_axis)))

# apply FK rotations (XYZ euler degrees, in bone local space)
for prefix, ang in P.get("bones", {}).items():
    b = pb(prefix)
    if not b:
        print("MISS BONE", prefix); continue
    b.rotation_mode = 'XYZ'
    b.rotation_euler = Euler(tuple(math.radians(a) for a in ang), 'XYZ')

bpy.context.view_layer.update()

for label, match in P.get("measure", {}).items():
    c = centroid(match)
    if c:
        tgt = P.get("targets", {}).get(label)
        d = (Vector(tgt) - c).length if tgt else -1
        print("MEASURE %-10s world (%+.3f %+.3f %+.3f)  dist_to_target %.4f" % (label, c.x, c.y, c.z, d))

# renders
sc = bpy.context.scene
try: sc.render.engine = 'BLENDER_EEVEE'
except TypeError: sc.render.engine = 'BLENDER_EEVEE_NEXT'
sc.render.resolution_x = 1000; sc.render.resolution_y = 640
sc.world = bpy.data.worlds.new("w"); sc.world.use_nodes = True
sc.world.node_tree.nodes["Background"].inputs[0].default_value = (0.12, 0.12, 0.15, 1)
for i, rot in enumerate([(math.radians(55), math.radians(5), math.radians(25)),
                          (math.radians(40), 0, math.radians(-140))]):
    ld = bpy.data.lights.new("k%d" % i, 'SUN'); ld.energy = 3.0
    lo = bpy.data.objects.new("k%d" % i, ld); lo.rotation_euler = rot
    sc.collection.objects.link(lo)
cam_data = bpy.data.cameras.new("cam"); cam = bpy.data.objects.new("cam", cam_data)
sc.collection.objects.link(cam); sc.camera = cam

views = {
    "side":  (Vector((1.3, -0.25, 0.15)), Vector((0, -0.05, -0.1)), 35),
    "front": (Vector((0.0, -1.4, 0.3)),  Vector((0, 0.1, -0.05)), 35),
    "fp":    (Vector(P["fp_cam_loc"]),   Vector(P["fp_cam_look"]),  None),
}
for name, (loc, look, lens) in views.items():
    cam.location = loc
    cam.rotation_euler = (look - loc).to_track_quat('-Z', 'Y').to_euler()
    if lens:
        cam_data.lens = lens
    else:
        cam_data.angle = math.radians(P.get("fp_fov", 75))
    sc.render.filepath = "%s_%s.png" % (out_prefix, name)
    bpy.ops.render.render(write_still=True)
print("POSE_OK")
