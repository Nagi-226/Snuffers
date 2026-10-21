# export_arms.py — pose + bake + stripes + EDAA patch + GLB export
# usage: blender -b --python export_arms.py -- <arms_glb> <weapon_proxy> <out_glb> <params.json> <emblem_png> <render_prefix> [base_tex_override]
import bpy, sys, math, json
from mathutils import Vector, Euler, Matrix

argv = sys.argv[sys.argv.index("--")+1:]
arms_glb, weapon_proxy, out_glb, params_path, emblem_png, render_prefix = argv[:6]
tex_override = argv[6] if len(argv) > 6 else None
P = json.load(open(params_path, encoding="utf-8"))

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=arms_glb)
for ob in list(bpy.data.objects):
    if ob.type == "MESH" and len(ob.data.vertices) < 100:
        bpy.data.objects.remove(ob, do_unlink=True)
if tex_override:
    # 换底图（手腕肤色带已涂深）+ 微弱自发光让夜景里手臂可读
    ov_img = bpy.data.images.load(tex_override)
    for mat in bpy.data.materials:
        if not mat.use_nodes:
            continue
        nt = mat.node_tree
        for n in nt.nodes:
            if n.type == 'TEX_IMAGE' and n.image and n.image.size[0] == ov_img.size[0]:
                n.image = ov_img
        bsd = next((n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED'), None)
        if bsd:
            texn = next((n for n in nt.nodes if n.type == 'TEX_IMAGE' and n.image == ov_img), None)
            if texn:
                nt.links.new(texn.outputs["Color"], bsd.inputs["Emission Color"])
            bsd.inputs["Emission Strength"].default_value = 0.35
bpy.ops.import_scene.gltf(filepath=weapon_proxy)
ws = P.get("weapon_scale", 1.0)
arm_ob = next(ob for ob in bpy.data.objects if ob.type == 'ARMATURE')
mesh = max((ob for ob in bpy.data.objects if ob.type == 'MESH' and ob.find_armature() == arm_ob),
           key=lambda o: len(o.data.vertices))
wep_meshes = [ob for ob in bpy.data.objects if ob.type == 'MESH' and ob.find_armature() != arm_ob]
if ws != 1.0:
    for ob in wep_meshes:
        ob.scale = (ws, ws, ws)

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

# ---- slim: rest-pose 网格编辑（与 pose_arms.py 同语义，保证预览=导出）----
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
    print("IK %-10s final_dist %.4f" % (meas, dist))

# ---- hand_aim: world-space hand orientation (same semantics as pose_arms.py) ----
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
    C = (_aim_basis(f_tgt, p_tgt) @ _aim_basis(f_cur, p_cur).inverted()).to_4x4()
    new_world = C @ (arm_ob.matrix_world @ b.matrix)
    b.matrix = arm_ob.matrix_world.inverted() @ new_world
    bpy.context.view_layer.update()
    print("AIM %-8s fingers->%s palm->%s" % (name, aim["fingers"], aim["palm"]))

for prefix, ang in P.get("bones", {}).items():
    b = pb(prefix)
    if b:
        b.rotation_mode = 'XYZ'
        b.rotation_euler = Euler(tuple(math.radians(a) for a in ang), 'XYZ')
bpy.context.view_layer.update()

# capture anatomical landmarks BEFORE bake
lm = {}
for side in ("R", "L"):
    lm["elbow_" + side] = centroid("forearm." + side)
    lm["wrist_" + side] = centroid("hand." + side)
    lm["upper_" + side] = centroid("upper_arm." + side)
print("LM", {k: tuple(round(c, 3) for c in v) for k, v in lm.items()})

# ---- bake: evaluated mesh -> new object ----
dg = bpy.context.evaluated_depsgraph_get()
ev = mesh.evaluated_get(dg)
baked_me = bpy.data.meshes.new_from_object(ev, depsgraph=dg)
baked = bpy.data.objects.new("arms_baked", baked_me)
bpy.context.scene.collection.objects.link(baked)
baked.matrix_world = ev.matrix_world.copy()
for m in mesh.data.materials:
    baked_me.materials.append(m)

# remove rig + original + weapon
for ob in list(bpy.data.objects):
    if ob != baked:
        bpy.data.objects.remove(ob, do_unlink=True)

bpy.ops.object.select_all(action='DESELECT')
baked.select_set(True)
bpy.context.view_layer.objects.active = baked
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

# ---- emissive cyan bands around forearms ----
band_mat = bpy.data.materials.new("edaa_glow")
band_mat.use_nodes = True
nt = band_mat.node_tree
bsdf = nt.nodes["Principled BSDF"]
bsdf.inputs["Base Color"].default_value = (0.02, 0.08, 0.10, 1)
bsdf.inputs["Emission Color"].default_value = (0.15, 0.85, 0.95, 1)
bsdf.inputs["Emission Strength"].default_value = 6.0
bsdf.inputs["Roughness"].default_value = 0.4

dg = bpy.context.evaluated_depsgraph_get()

def add_band(center, axis, name):
    axis = axis.normalized()
    bpy.ops.mesh.primitive_torus_add(major_radius=0.052, minor_radius=0.0035,
                                     major_segments=24, minor_segments=6,
                                     location=center)
    band = bpy.context.view_layer.objects.active
    band.name = name
    q = Vector((0, 0, 1)).rotation_difference(axis)
    band.rotation_mode = 'QUATERNION'
    band.rotation_quaternion = q
    band.data.materials.append(band_mat)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    mod = band.modifiers.new("sw", 'SHRINKWRAP')
    mod.target = baked
    mod.offset = 0.0015
    mod.wrap_method = 'PROJECT'
    mod.use_project_z = True
    bpy.context.view_layer.objects.active = band
    try:
        bpy.ops.object.modifier_apply(modifier="sw")
    except RuntimeError:
        print("SW_FAIL", name)

for side in ("R", "L"):
    elbow, wrist = lm["elbow_" + side], lm["wrist_" + side]
    axis = elbow - wrist
    if P.get("add_glow_bands", False):
        for i, t in enumerate((0.25, 0.45)):
            c = wrist + axis * t
            add_band(c, axis, "glow_%s_%d" % (side, i))

# ---- EDAA patch on right upper arm ----
upperR = lm["upper_R"]
out_dir = Vector((1, 0, 0))
img = bpy.data.images.load(emblem_png)
patch_mat = bpy.data.materials.new("edaa_patch")
patch_mat.use_nodes = True
pnt = patch_mat.node_tree
pbsdf = pnt.nodes["Principled BSDF"]
texn = pnt.nodes.new("ShaderNodeTexImage")
texn.image = img
pnt.links.new(texn.outputs["Color"], pbsdf.inputs["Base Color"])
pbsdf.inputs["Roughness"].default_value = 0.7
pbsdf.inputs["Emission Color"].default_value = (1, 1, 1, 1)
pbsdf.inputs["Emission Strength"].default_value = 0.25
pnt.links.new(texn.outputs["Color"], pbsdf.inputs["Emission Color"])

# raycast from outside toward upper arm to find surface point + normal
sc = bpy.context.scene
dg = bpy.context.evaluated_depsgraph_get()
origin = upperR + Vector((0.6, 0, 0.05))
direction = (upperR - origin).normalized()
res = sc.ray_cast(dg, origin, direction)
hit, loc, norm = res[0], res[1], res[2]
if hit:
    ploc = loc + norm * 0.004
    bpy.ops.mesh.primitive_plane_add(size=1.0, location=ploc)
    patch = bpy.context.view_layer.objects.active
    patch.name = "edaa_patch_r"
    patch.scale = (0.030, 0.038, 1.0)
    q = Vector((0, 0, 1)).rotation_difference(norm)
    patch.rotation_mode = 'QUATERNION'
    patch.rotation_quaternion = q
    patch.data.materials.append(patch_mat)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=False)
    mod = patch.modifiers.new("sw", 'SHRINKWRAP')
    mod.target = baked; mod.offset = 0.002; mod.wrap_method = 'PROJECT'; mod.use_project_z = True
    bpy.context.view_layer.objects.active = patch
    try:
        bpy.ops.object.modifier_apply(modifier="sw")
    except RuntimeError:
        print("SW_FAIL patch")
    print("PATCH_OK", tuple(round(v, 3) for v in ploc))
else:
    print("PATCH_MISS")

# ---- render validation ----
sc = bpy.context.scene
try:
    sc.render.engine = 'BLENDER_EEVEE'
except TypeError:
    sc.render.engine = 'BLENDER_EEVEE_NEXT'
sc.render.resolution_x = 1000; sc.render.resolution_y = 640
sc.world = bpy.data.worlds.new("w"); sc.world.use_nodes = True
sc.world.node_tree.nodes["Background"].inputs[0].default_value = (0.05, 0.05, 0.07, 1)
for i, rot in enumerate([(math.radians(55), math.radians(5), math.radians(25)),
                          (math.radians(40), 0, math.radians(-140))]):
    ld = bpy.data.lights.new("k%d" % i, 'SUN'); ld.energy = 2.0
    lo = bpy.data.objects.new("k%d" % i, ld); lo.rotation_euler = rot
    sc.collection.objects.link(lo)
cam_data = bpy.data.cameras.new("cam"); cam = bpy.data.objects.new("cam", cam_data)
sc.collection.objects.link(cam); sc.camera = cam
views = {
    "side": (Vector((1.3, -0.25, 0.15)), Vector((0, -0.05, -0.1)), 35),
    "fp":   (Vector(P["fp_cam_loc"]), Vector(P["fp_cam_look"]), None),
}
for name, (loc2, look, lens) in views.items():
    cam.location = loc2
    cam.rotation_euler = (look - loc2).to_track_quat('-Z', 'Y').to_euler()
    if lens:
        cam_data.lens = lens
    else:
        cam_data.angle = math.radians(P.get("fp_fov", 75))
    sc.render.filepath = "%s_%s.png" % (render_prefix, name)
    bpy.ops.render.render(write_still=True)

# ---- export ----
bpy.ops.object.select_all(action='SELECT')
bpy.ops.export_scene.gltf(filepath=out_glb, export_yup=True, export_apply=False)
print("EXPORT_OK", out_glb)
