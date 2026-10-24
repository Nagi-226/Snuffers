# export_arms.py — pose + bake + stripes + EDAA patch + GLB export
# usage: blender -b --python export_arms.py -- <arms_glb> <weapon_proxy> <out_glb> <params.json> <emblem_png> <render_prefix> [base_tex_override]
import bpy, sys, math, json, os
from mathutils import Vector, Euler, Matrix

argv = sys.argv[sys.argv.index("--")+1:]
arms_glb, weapon_proxy, out_glb, params_path, emblem_png, render_prefix = argv[:6]
tex_override = argv[6] if len(argv) > 6 else None
if not os.path.isabs(render_prefix):
    render_prefix = os.path.join(os.path.dirname(os.path.abspath(__file__)), render_prefix)
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
                gain = nt.nodes.new("ShaderNodeMixRGB")
                gain.blend_type = 'MULTIPLY'
                gain.inputs[0].default_value = 1.0
                gain.inputs[2].default_value = (P.get("albedo_gain", 1.0),) * 3 + (1.0,)
                nt.links.new(texn.outputs["Color"], gain.inputs[1])
                nt.links.new(gain.outputs[0], bsd.inputs["Base Color"])
                nt.links.new(gain.outputs[0], bsd.inputs["Emission Color"])
            bsd.inputs["Emission Strength"].default_value = P.get("emission_strength", 0.35)
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

if P.get("reload"):
    bpy.ops.object.select_all(action='DESELECT')
    arm_ob.select_set(True)
    bpy.context.view_layer.objects.active = arm_ob
    bpy.ops.object.mode_set(mode='EDIT')
    magazine_bone = arm_ob.data.edit_bones.new("magazine_motion")
    magazine_bone.matrix = Matrix.Identity(4)
    magazine_bone.length = 0.02
    bpy.ops.object.mode_set(mode='OBJECT')
    arm_ob.pose.bones["magazine_motion"].matrix = Matrix.Identity(4)
    bpy.context.view_layer.update()

base_pose = {b.name: b.matrix.copy() for b in arm_ob.pose.bones}
for b in arm_ob.pose.bones:
    basis = b.matrix_basis.copy()
    b.rotation_mode = 'QUATERNION'
    b.location = basis.translation
    b.rotation_quaternion = basis.to_quaternion()
    b.scale = basis.to_scale()
bpy.context.view_layer.update()
base_basis = {b.name: b.matrix_basis.copy() for b in arm_ob.pose.bones}
reload_cfg = P.get("reload")
if reload_cfg:
    target_scene = bpy.context.scene
    project_root = os.path.abspath(os.path.join(os.path.dirname(__file__), "../../../.."))
    source_path = reload_cfg["source"]
    if not os.path.isabs(source_path):
        source_path = os.path.join(project_root, source_path)
    source_scene = bpy.data.scenes.new("cransh_source")
    bpy.context.window.scene = source_scene
    bpy.ops.import_scene.gltf(filepath=source_path)
    source_arm = next(ob for ob in source_scene.objects if ob.type == 'ARMATURE')
    source_arm.animation_data_create()
    source_arm.animation_data.action = bpy.data.actions[reload_cfg["clip"]]
    source_scene.frame_set(1)
    bpy.context.view_layer.update()
    source_reference = {b.name: b.matrix.copy() for b in source_arm.pose.bones}
    source_basis_reference = {b.name: b.matrix_basis.copy() for b in source_arm.pose.bones}

    bone_map = {
        "upper_arm.L": "UpArm_L", "forearm.L": "Forearm_L", "hand.L": "Hand_L",
        "upper_arm.R": "UpArm_R", "forearm.R": "Forearm_R", "hand.R": "Hand_R",
    }
    for side in ("L", "R"):
        for finger, offset in (("thumb", 4), ("f_index", 8), ("f_middle", 12),
                               ("f_ring", 16), ("f_pinky", 20)):
            for joint in range(1, 4):
                bone_map["%s.%02d.%s" % (finger, joint, side)] = "Bone_%s.%03d" % (
                    side, offset + joint - 1)
    mapped_bones = [(pb(target), next(b for b in source_arm.pose.bones
                                      if b.name.startswith(source + "_")))
                    for target, source in bone_map.items()]
    mapped_bones.sort(key=lambda pair: len(pair[0].parent_recursive))
    motion_scale = sum((base_pose[target.name].translation -
                        base_pose[target.parent.name].translation).length /
                       (source_reference[source.name].translation -
                        source_reference[source.parent.name].translation).length
                       for target, source in mapped_bones if target.name.startswith("forearm")) * 0.5
    motion_scale *= reload_cfg.get("translation_scale", 1.0)

    reference_hand = next(b for b in source_arm.pose.bones if b.name.startswith("Hand_R_"))
    source_weapon = next(b for b in source_arm.pose.bones
                         if b.name.startswith(("ACRRifle_", "PBody_")))
    source_weapon_world = source_arm.matrix_world @ source_reference[source_weapon.name]
    alignment = (arm_ob.matrix_world.inverted() @ source_weapon_world).to_3x3().to_quaternion().to_matrix()
    finger_bones = [(target, source) for target, source in mapped_bones
                    if target.name.startswith(("f_", "thumb"))]
    source_left = next(b for b in source_arm.pose.bones if b.name.startswith("Hand_L_"))
    source_magazine = next(b for b in source_arm.pose.bones if b.name.startswith("Pmag_"))
    magazine_bone = pb("magazine_motion")

    def set_local_matrix(bone, local_pose):
        bone.location = local_pose.translation
        bone.rotation_quaternion = local_pose.to_quaternion()
        bone.scale = local_pose.to_scale()

    def set_pose_matrix(bone, pose):
        if bone.parent is None:
            local_pose = bone.bone.matrix_local.inverted() @ pose
        else:
            relative_rest = bone.parent.bone.matrix_local.inverted() @ bone.bone.matrix_local
            local_pose = (bone.parent.matrix @ relative_rest).inverted() @ pose
        set_local_matrix(bone, local_pose)

    def place_hand(side, delta, wrist_override = None):
        upper = pb("upper_arm." + side)
        forearm = pb("forearm." + side)
        hand = pb("hand." + side)
        root = base_pose[upper.name].translation
        elbow0 = base_pose[forearm.name].translation
        wrist0 = base_pose[hand.name].translation
        upper_length = (elbow0 - root).length
        forearm_length = (wrist0 - elbow0).length
        wrist = wrist0 + alignment @ (delta.translation * motion_scale)
        if wrist_override is not None:
            wrist = wrist_override
        direction = (wrist - root).normalized()
        reach = min(max((wrist - root).length, abs(upper_length - forearm_length) + 0.001),
                    upper_length + forearm_length - 0.001)
        wrist = root + direction * reach
        pole = elbow0 - root
        pole = (pole - direction * pole.dot(direction)).normalized()
        angle = math.acos(max(-1.0, min(1.0,
            (upper_length ** 2 + reach ** 2 - forearm_length ** 2) /
            (2.0 * upper_length * reach))))
        elbow = root + (direction * math.cos(angle) + pole * math.sin(angle)) * upper_length
        upper_rotation = (elbow0 - root).rotation_difference(elbow - root) @ base_pose[upper.name].to_quaternion()
        fore_rotation = (wrist0 - elbow0).rotation_difference(wrist - elbow) @ base_pose[forearm.name].to_quaternion()
        set_pose_matrix(upper, Matrix.LocRotScale(root, upper_rotation, base_pose[upper.name].to_scale()))
        bpy.context.view_layer.update()
        set_pose_matrix(forearm, Matrix.LocRotScale(elbow, fore_rotation, base_pose[forearm.name].to_scale()))
        bpy.context.view_layer.update()
        source_hand = next(b for b in source_arm.pose.bones if b.name.startswith("Hand_" + side + "_"))
        source_rotation = (delta @ source_reference[source_hand.name]).to_quaternion()
        hand_alignment = base_pose[hand.name].to_quaternion() @ source_reference[source_hand.name].to_quaternion().inverted()
        set_pose_matrix(hand, Matrix.LocRotScale(wrist,
            hand_alignment @ source_rotation, Vector((1, 1, 1))))
        bpy.context.view_layer.update()

    bpy.context.window.scene = target_scene
    arm_ob.animation_data_create()
    action = bpy.data.actions.new("reload")
    action.use_fake_user = True
    arm_ob.animation_data.action = action
    target_scene.render.fps = 60
    mapped_names = {target.name for target, source in mapped_bones}
    for b in arm_ob.pose.bones:
        if b.name not in mapped_names:
            b.matrix_basis = base_basis[b.name]
            b.keyframe_insert("location", frame=1, group=b.name)
            b.keyframe_insert("rotation_quaternion", frame=1, group=b.name)
            b.keyframe_insert("scale", frame=1, group=b.name)
    for frame in range(1, round(reload_cfg["duration"] * 60) + 2):
        fraction = (frame - 1) / (round(reload_cfg["duration"] * 60) - 1)
        bpy.context.window.scene = source_scene
        sample = 1.0 + fraction * (source_arm.animation_data.action.frame_range[1] - 1.0)
        source_scene.frame_set(int(sample), subframe=sample % 1.0)
        bpy.context.view_layer.update()
        deltas = {target.name: source.matrix @ source_reference[source.name].inverted()
                  for target, source in mapped_bones}
        bpy.context.window.scene = target_scene
        target_scene.frame_set(frame)
        for target in sorted(arm_ob.pose.bones, key=lambda bone: len(bone.parent_recursive)):
            target.matrix = base_pose[target.name]
            bpy.context.view_layer.update()
        place_hand("R", Matrix.Identity(4))
        magazine_offset = ((source_magazine.matrix.translation - reference_hand.matrix.translation) -
                           (source_reference[source_magazine.name].translation - source_reference[reference_hand.name].translation))
        left_delta = deltas[pb("hand.L").name].copy()
        left_delta.translation = ((source_left.matrix.translation - reference_hand.matrix.translation) -
                                  (source_reference[source_left.name].translation - source_reference[reference_hand.name].translation))
        lift_weight = min(1.0, magazine_offset.length / 0.08)
        lift_weight = lift_weight * lift_weight * (3.0 - 2.0 * lift_weight)
        lift = Vector((-reload_cfg.get("reload_center", 0.0) * lift_weight, 0,
                       reload_cfg.get("reload_lift", 0.0) * lift_weight))
        left_wrist = base_pose[pb("hand.L").name].translation + alignment @ (left_delta.translation * motion_scale) - lift
        place_hand("L", left_delta, left_wrist)
        for target, source in finger_bones:
            delta = source.matrix_basis @ source_basis_reference[source.name].inverted()
            set_local_matrix(target, Matrix.LocRotScale(base_basis[target.name].translation,
                base_basis[target.name].to_quaternion() @ delta.to_quaternion(),
                base_basis[target.name].to_scale()))
        magazine_delta = (source_magazine.matrix @ source_reference[source_magazine.name].inverted() @
                          deltas[pb("hand.R").name].inverted())
        magazine_translation = alignment @ (magazine_offset * motion_scale) + lift
        magazine_pose = Matrix.LocRotScale(magazine_translation,
            (alignment @ magazine_delta.to_quaternion().to_matrix() @ alignment.inverted()).to_quaternion(),
            Vector((1, 1, 1)))
        set_pose_matrix(magazine_bone, magazine_pose)
        bpy.context.view_layer.update()
        assert (magazine_bone.matrix.translation - magazine_translation).length < 0.00001, \
            "Magazine motion must share the armature-space translation with the left hand"
        for b, source in mapped_bones + [(magazine_bone, source_magazine)]:
            b.keyframe_insert("location", frame=frame, group=b.name)
            b.keyframe_insert("rotation_quaternion", frame=frame, group=b.name)
            b.keyframe_insert("scale", frame=frame, group=b.name)
        bpy.context.view_layer.update()
    for b in arm_ob.pose.bones:
        b.matrix = base_pose[b.name]
    bpy.context.view_layer.update()
    target_scene.frame_set(1)
    first_frame_errors = sorted(((b.matrix.translation - base_pose[b.name].translation).length, b.name)
                                for b in arm_ob.pose.bones)
    assert first_frame_errors[-1][0] < 0.001, "Reload first frame changed grip pose: %s" % first_frame_errors[-5:]
    target_scene.frame_end = round(reload_cfg["duration"] * 60)
    print("RETARGET_OK", reload_cfg["clip"], "mapped_bones", len(mapped_bones),
          "motion_scale", motion_scale, "duration", reload_cfg["duration"])
    for source_action in list(bpy.data.actions):
        if source_action != action:
            bpy.data.actions.remove(source_action)
    bpy.data.scenes.remove(source_scene)

# capture anatomical landmarks BEFORE bake
lm = {}
for side in ("R", "L"):
    lm["elbow_" + side] = centroid("forearm." + side)
    lm["wrist_" + side] = centroid("hand." + side)
    lm["upper_" + side] = centroid("upper_arm." + side)
print("LM", {k: tuple(round(c, 3) for c in v) for k, v in lm.items()})

# ---- bake static version, or retain the original bound mesh for animation ----
dg = bpy.context.evaluated_depsgraph_get()
ev = mesh.evaluated_get(dg)
if reload_cfg:
    baked = mesh
    baked_me = mesh.data
    baked_world = mesh.matrix_world.copy()
else:
    baked_me = bpy.data.meshes.new_from_object(ev, depsgraph=dg)
    baked = bpy.data.objects.new("arms_baked", baked_me)
    bpy.context.scene.collection.objects.link(baked)
    baked_world = ev.matrix_world.copy()
    baked.matrix_world = baked_world
    for m in mesh.data.materials:
        baked_me.materials.append(m)

for ob in list(bpy.data.objects):
    if ob != baked and ob != arm_ob:
        bpy.data.objects.remove(ob, do_unlink=True)

if reload_cfg and baked.data.materials:
    glove_mat = baked.data.materials[0].copy()
    glove_mat.name = "arms_glove_readability"
    for node in glove_mat.node_tree.nodes:
        if node.type == 'MIX_RGB' and node.blend_type == 'MULTIPLY':
            node.inputs[2].default_value = (P.get("glove_gain", 6.0),) * 3 + (1.0,)
    baked.data.materials.append(glove_mat)
    glove_index = len(baked.data.materials) - 1
    hand_groups = {group.index for group in baked.vertex_groups
                   if group.name.startswith(("hand.", "palm.", "f_", "thumb."))}
    hand_faces = 0
    for polygon in baked.data.polygons:
        weight = sum(group.weight for vertex_index in polygon.vertices
                     for group in baked.data.vertices[vertex_index].groups
                     if group.group in hand_groups) / len(polygon.vertices)
        if weight > 0.55:
            polygon.material_index = glove_index
            hand_faces += 1
    print("GLOVE_FACES", hand_faces)

if not reload_cfg:
    bpy.ops.object.select_all(action='DESELECT')
    baked.select_set(True)
    bpy.context.view_layer.objects.active = baked
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    armature_mod = baked.modifiers.new("Armature", "ARMATURE")
    armature_mod.object = arm_ob
    baked.parent = arm_ob
    baked.matrix_world = baked_world

# ---- remove_groups: 删除指定顶点组主导的网格段 ----
# 2026-10-21 机主裁决（手枪 ADS）：上臂段在镜筒视角两侧形成鼓包，删去只留
# 平直前臂，肘端藏到屏幕底缘之外。顶点组随 new_from_object 保留在烘焙网格上。
_rg = P.get("remove_groups", [])
if _rg:
    import bmesh
    _thresh = P.get("remove_group_weight", 0.4)
    _idxs = [g.index for g in baked.vertex_groups
             if any(g.name.startswith(p) for p in _rg)]
    _bm = bmesh.new()
    _bm.from_mesh(baked_me)
    _dl = _bm.verts.layers.deform.active
    _doomed = [v for v in _bm.verts
               if any(v[_dl].get(gi, 0.0) > _thresh for gi in _idxs)]
    bmesh.ops.delete(_bm, geom=_doomed, context='VERTS')
    _bm.to_mesh(baked_me)
    _bm.free()
    print("REMOVE_GROUPS", _rg, "verts", len(_doomed))

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

# ---- EDAA patch（默认右上臂；patch_target="forearm" 时贴右前臂外侧——
# 上臂段被 remove_groups 删除后 EDAA 臂章不能丢，改贴前臂袖面）----
upperR = lm["elbow_R"] if P.get("patch_target") == "forearm" else lm["upper_R"]
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

# ---- sleeve extenders: 延长上臂袖管越过相机近平面，消除开镜视角的手臂截断面 ----
# 原理：烘焙网格在肩端被源模型截断，开镜时相机直视截断面。沿上臂轴线（肘→肩方向
# 继续延伸）加一段渐缩圆锥管接续袖子，末端伸到近平面之后/视野之外，截断面即不可见。
# 半径取固定值（收细后的袖子约 0.07~0.09m 半径），比实测稳健——实测会被腋部/对侧
# 沿轴投影的杂散顶点污染。深色材质 + 与手臂一致的自发光强度（tex_override 设 0.35），
# 夜景下与深色袖面观感一致。
ext_mat = bpy.data.materials.new("sleeve_ext")
ext_mat.use_nodes = True
ebsdf = ext_mat.node_tree.nodes["Principled BSDF"]
ebsdf.inputs["Base Color"].default_value = (0.001, 0.001, 0.001, 1)
ebsdf.inputs["Roughness"].default_value = 1.0
# 夜景关卡里纯黑延长管即「隐形接续」：藏住截断面又不引入任何可见轮廓，
# 比试图匹配袖面颜色稳健（臂面贴图极暗，任何有限反照率在暗渲染下都会显白）。
ebsdf.inputs["Emission Strength"].default_value = 0.0

for side in ("R", "L"):
    if P.get("skip_sleeve_ext", False):
        break
    elbow, upper = lm["elbow_" + side], lm["upper_" + side]
    axis = upper - elbow
    if axis.length < 1e-6:
        continue
    axis = axis.normalized()
    start = upper - axis * 0.04
    end = upper + axis * 0.6
    mid = (start + end) * 0.5
    bpy.ops.mesh.primitive_cone_add(vertices=16, radius1=0.06, radius2=0.035,
                                    depth=(end - start).length,
                                    end_fill_type='NGON', location=mid)
    tube = bpy.context.view_layer.objects.active
    tube.name = "sleeve_ext_" + side
    tube.rotation_mode = 'QUATERNION'
    # cone 的 radius1 在 -Z 端：让 -Z 指向 start（肘侧），+Z 朝肩后渐缩
    tube.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(axis)
    tube.data.materials.append(ext_mat)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    print("SLEEVE_EXT %s" % side)

for ob in list(bpy.context.scene.objects):
    if ob.type != 'MESH' or ob == baked:
        continue
    bone = None
    if ob.name.startswith("glow_"):
        bone = "forearm." + ob.name.split("_")[1]
    elif ob.name.startswith("sleeve_ext_"):
        bone = "upper_arm." + ob.name.rsplit("_", 1)[-1]
    elif ob.name == "edaa_patch_r":
        bone = "forearm.R" if P.get("patch_target") == "forearm" else "upper_arm.R"
    if bone:
        world = ob.matrix_world.copy()
        ob.parent = arm_ob
        ob.parent_type = 'BONE'
        ob.parent_bone = pb(bone).name
        ob.matrix_world = world

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
bpy.ops.export_scene.gltf(filepath=out_glb, export_yup=True, export_apply=False,
                          export_animations=bool(reload_cfg), export_animation_mode='ACTIONS',
                          export_rest_position_armature=False, export_anim_slide_to_zero=True)
print("EXPORT_OK", out_glb)
