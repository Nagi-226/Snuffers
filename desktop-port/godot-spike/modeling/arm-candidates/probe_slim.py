import bpy, sys, os
from mathutils import Vector

argv = sys.argv[sys.argv.index("--")+1:]
arms_glb = argv[0]

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=arms_glb)
arm_ob = next(ob for ob in bpy.data.objects if ob.type == 'ARMATURE')
mesh = max((ob for ob in bpy.data.objects if ob.type == 'MESH' and ob.find_armature() == arm_ob),
           key=lambda o: len(o.data.vertices))

print("=== BONES ===")
for b in arm_ob.data.bones:
    h = arm_ob.matrix_world @ b.head_local
    t = arm_ob.matrix_world @ b.tail_local
    print("BONE %-18s head(%+.3f %+.3f %+.3f) tail(%+.3f %+.3f %+.3f) parent=%s" % (
        b.name, h.x, h.y, h.z, t.x, t.y, t.z, b.parent.name if b.parent else "-"))

print("=== VERTEX GROUPS ===")
vg = {g.index: g.name for g in mesh.vertex_groups}
stats = {}
for v in mesh.data.vertices:
    best_w, best_g = 0.0, None
    for g in v.groups:
        if g.weight > best_w:
            best_w, best_g = g.weight, vg.get(g.group, "?")
    stats[best_g] = stats.get(best_g, 0) + 1
for name, n in sorted(stats.items(), key=lambda kv: -kv[1]):
    print("VG %-20s %d verts (dominant)" % (name, n))

# 上臂顶点的径向厚度测量（相对 upper_arm 骨骼轴线）
mw = mesh.matrix_world
for side in ("R", "L"):
    bn = "upper_arm." + side
    b = arm_ob.data.bones.get(bn)
    if not b:
        continue
    h = arm_ob.matrix_world @ b.head_local
    t = arm_ob.matrix_world @ b.tail_local
    axis = (t - h).normalized()
    radii = []
    for v in mesh.data.vertices:
        w = sum(g.weight for g in v.groups if vg.get(g.group, "") == bn)
        if w < 0.5:
            continue
        p = mw @ v.co
        tt = max(0.0, min(1.0, (p - h).dot(axis) / (t - h).length))
        cp = h + axis * tt * (t - h).length
        radii.append((tt, (p - cp).length))
    if radii:
        near_head = [r for tt, r in radii if tt < 0.33]
        mid = [r for tt, r in radii if 0.33 <= tt < 0.66]
        near_elbow = [r for tt, r in radii if tt >= 0.66]
        print("UPPERARM %s: n=%d  radius head=%.4f mid=%.4f elbow=%.4f (bone len %.4f)" % (
            side, len(radii),
            max(near_head) if near_head else -1,
            max(mid) if mid else -1,
            max(near_elbow) if near_elbow else -1,
            (t - h).length))
print("PROBE_OK")
