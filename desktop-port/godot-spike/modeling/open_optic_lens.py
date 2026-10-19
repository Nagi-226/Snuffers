import bpy, sys, json, math

argv = sys.argv[sys.argv.index("--") + 1:]
src, dst = argv[0], argv[1]

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)

optic = bpy.data.objects.get("em68a_optic")
assert optic is not None, "em68a_optic not found"

# 包围盒（局部空间）
import mathutils
bb = [mathutils.Vector(c) for c in optic.bound_box]  # local space
min_x = min(v.x for v in bb); max_x = max(v.x for v in bb)
min_y = min(v.y for v in bb); max_y = max(v.y for v in bb)
min_z = min(v.z for v in bb); max_z = max(v.z for v in bb)
cx = (min_x + max_x) / 2
span_x = max_x - min_x
span_z = max_z - min_z

# 镜筒通孔判定（v4，两阶段）：
# 阶段一——用法线近轴向(|n.y|>0.8)的面片估出镜片平面高度 z0 与镜孔半径 r；
# 阶段二——以 (cx, z0) 为轴心、1.15r 为半径做圆柱，柱内面片不分深度一律删除，
# 弧面镜片/前后盖/内部遮光环全清空，形成真正可透视的镜筒通道。
import mathutils
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

report = {"candidate_faces": len(sel), "total_faces": len(mesh.polygons), "bore_z0": z0, "bore_r": r}

# 安全闸：候选面超过总量 45% 说明判定过宽，放弃（AI 网格极密，孔柱内面数可能上万）
assert len(sel) < len(mesh.polygons) * 0.45, "too many candidate faces: %d" % len(sel)
assert len(sel) > 0, "no candidate faces found"

# 删除选中面
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

# 其它对象面数核对（零改动）
others = {o.name: len(o.data.polygons) for o in bpy.data.objects if o.type == "MESH" and o.name != "em68a_optic"}
report["others"] = others

bpy.ops.export_scene.gltf(filepath=dst, export_format="GLB", export_yup=True,
                          export_apply=False, export_animations=False)

# ===== 透视验证渲染：从镜筒后端沿轴向看向筒内，应看到通透（背景色穿过来）=====
import mathutils
scene = bpy.context.scene
scene.render.engine = "BLENDER_WORKBENCH"
scene.display.shading.light = "STUDIO"
scene.display.shading.color_type = "MATERIAL"
scene.render.resolution_x = 512
scene.render.resolution_y = 512
scene.world = bpy.data.worlds.new("W")
scene.world.color = (0.2, 0.5, 0.8)  # 亮蓝背景：筒内通透则可见蓝

center_local = mathutils.Vector((cx, (min_y + max_y) / 2, z0))
center_world = optic.matrix_world @ center_local
axis_world = (optic.matrix_world.to_quaternion() @ mathutils.Vector((0, 1, 0))).normalized()

cam_data = bpy.data.cameras.new("VerifyCam")
cam = bpy.data.objects.new("VerifyCam", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam
cam_data.clip_start = 0.001

for tag, sign in [("rear", -1.0), ("front", 1.0)]:
    cam.location = center_world + axis_world * sign * 0.35
    look_target = center_world - axis_world * sign  # 朝筒内看
    direction = (look_target - cam.location).normalized()
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = dst.replace(".glb", "_verify_%s.png" % tag)
    bpy.ops.render.render(write_still=True)

report["bore_local_blender"] = {"x": cx, "y_mid": (min_y + max_y) / 2, "z0": z0}
print("LENSOP " + json.dumps(report))
