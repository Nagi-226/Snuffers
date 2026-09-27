# build_owl_drone.py — 「鸮」球形自主侦察无人机程序化建模
# 用法: blender -b --python build_owl_drone.py
# 产物: godot/assets/models/owl_drone.glb + 同目录 preview PNG
# 100% 程序化生成，无外部资产，无网络访问。
import bpy
import math
import os
import sys

# ---------- 输出路径 ----------
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
# 脚本位于 <repo>/desktop-port/godot-spike/modeling/，上溯三级到仓库根
PROJECT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", "..", ".."))
OUT_DIR = os.path.join(PROJECT_ROOT, "godot", "assets", "models")
os.makedirs(OUT_DIR, exist_ok=True)
GLB_PATH = os.path.join(OUT_DIR, "owl_drone.glb")
PREVIEW_PATH = os.path.join(OUT_DIR, "owl_drone_preview.png")

# ---------- 场景重置 ----------
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.unit_settings.system = 'METRIC'
scene.unit_settings.scale_length = 1.0

# ---------- 材质 ----------
def make_material(name, base_color, metallic=0.0, roughness=0.5,
                  emission_color=None, emission_strength=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*base_color, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if emission_color is not None:
        em_input = bsdf.inputs.get("Emission Color") or bsdf.inputs.get("Emission")
        if em_input is not None:
            em_input.default_value = (*emission_color, 1.0)
        strength_input = bsdf.inputs.get("Emission Strength")
        if strength_input is not None:
            strength_input.default_value = emission_strength
    return mat

MAT_HULL = make_material("MAT_Owl_Hull", (0.045, 0.05, 0.06), metallic=0.9, roughness=0.42)
MAT_RING = make_material("MAT_Owl_Ring", (0.02, 0.02, 0.025), metallic=0.9, roughness=0.3)
MAT_EYE  = make_material("MAT_Owl_Eye", (0.01, 0.02, 0.04), metallic=0.3, roughness=0.08,
                         emission_color=(0.05, 0.55, 0.9), emission_strength=4.0)
MAT_TRIM = make_material("MAT_Owl_Trim", (0.3, 0.02, 0.015), metallic=0.5, roughness=0.55,
                         emission_color=(0.5, 0.03, 0.02), emission_strength=0.35)

# ---------- 几何构建 ----------
created = []

def add_uv_sphere(name, radius, location, scale=(1, 1, 1), mat=None, segments=48, rings=24):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=radius, segments=segments,
                                         ring_count=rings, location=location)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(scale=True)
    if mat:
        obj.data.materials.append(mat)
    for poly in obj.data.polygons:
        poly.use_smooth = True
    created.append(obj)
    return obj

def add_torus(name, major, minor, location, rotation=(0, 0, 0), mat=None):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor,
                                     major_segments=64, minor_segments=12,
                                     location=location, rotation=rotation)
    obj = bpy.context.active_object
    obj.name = name
    if mat:
        obj.data.materials.append(mat)
    for poly in obj.data.polygons:
        poly.use_smooth = True
    created.append(obj)
    return obj

def add_cylinder(name, radius, depth, location, rotation=(0, 0, 0), mat=None, vertices=24):
    bpy.ops.mesh.primitive_cylinder_add(radius=radius, depth=depth, vertices=vertices,
                                        location=location, rotation=rotation)
    obj = bpy.context.active_object
    obj.name = name
    if mat:
        obj.data.materials.append(mat)
    created.append(obj)
    return obj

# 主球体（机体），原点在球心，直径 0.5m
add_uv_sphere("Owl_Body", 0.25, (0, 0, 0), mat=MAT_HULL)

# 赤道传感环（黑色环带）
add_torus("Owl_SensorRing", 0.255, 0.028, (0, 0, 0), mat=MAT_RING)

# 红色识别饰条（环外侧细圈，EDAA 装备识别色）
add_torus("Owl_TrimStripe", 0.262, 0.008, (0, 0, 0.045), mat=MAT_TRIM)

# 主光学「眼」— 前向 -Y（glTF 导出后为 +Z 前向惯例）
# 镜头外圈
add_cylinder("Owl_EyeBezel", 0.062, 0.035, (0, -0.235, 0.02),
             rotation=(math.radians(90), 0, 0), mat=MAT_RING)
# 发光镜头
add_uv_sphere("Owl_Eye", 0.05, (0, -0.25, 0.02), scale=(1, 0.42, 1), mat=MAT_EYE)

# 顶部天线短柱
add_cylinder("Owl_Antenna", 0.012, 0.09, (0, 0.02, 0.28), mat=MAT_RING)
add_uv_sphere("Owl_AntennaTip", 0.02, (0, 0.02, 0.33), mat=MAT_TRIM, segments=24, rings=12)

# 背部 3 个微型推进器喷口（120° 分布）
for i in range(3):
    ang = math.radians(i * 120)
    x, y = math.cos(ang) * 0.16, math.sin(ang) * 0.16 + 0.12
    add_cylinder("Owl_Thruster_%d" % i, 0.035, 0.05, (x, y, -0.12),
                 rotation=(math.radians(20), 0, -ang), mat=MAT_RING)

# ---------- 合并为单一网格（Godot 占位资产，单 Mesh 多材质槽） ----------
bpy.ops.object.select_all(action='DESELECT')
for obj in created:
    obj.select_set(True)
bpy.context.view_layer.objects.active = created[0]
bpy.ops.object.join()
drone = bpy.context.active_object
drone.name = "Owl_Drone"

# ---------- 导出 GLB ----------
bpy.ops.export_scene.gltf(
    filepath=GLB_PATH,
    export_format='GLB',
    export_yup=True,
    export_apply=True,
    export_animations=False,
)
print("KIMI_BLENDER_RESULT={\"glb\": \"%s\", \"verts\": %d}" % (
    GLB_PATH.replace("\\", "/"), len(drone.data.vertices)))

# ---------- 预览渲染 ----------
# 地面
bpy.ops.mesh.primitive_plane_add(size=4, location=(0, 0, -0.35))
plane = bpy.context.active_object
mat_ground = make_material("MAT_Ground", (0.06, 0.06, 0.07), roughness=0.9)
plane.data.materials.append(mat_ground)

# 相机
bpy.ops.object.camera_add(location=(0.85, -0.95, 0.55))
cam = bpy.context.active_object
direction = bpy.mathutils_Vector((0, 0, 0)) - cam.location if hasattr(bpy, 'mathutils_Vector') else None
import mathutils
direction = mathutils.Vector((0, 0, 0.02)) - cam.location
cam.rotation_euler = direction.to_track_quat('-Z', 'Y').to_euler()
scene.camera = cam

# 三点照明
def add_area(name, location, energy, size, color):
    bpy.ops.object.light_add(type='AREA', location=location)
    light = bpy.context.active_object
    light.name = name
    light.data.energy = energy
    light.data.shape = 'DISK'
    light.data.size = size
    light.data.color = color
    d = mathutils.Vector((0, 0, 0)) - light.location
    light.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
    return light

add_area("KeyLight", (1.2, -1.0, 1.5), 400, 0.8, (1.0, 0.95, 0.9))
add_area("FillLight", (-1.2, -0.6, 0.6), 200, 0.6, (0.7, 0.85, 1.0))
add_area("RimLight", (0.3, 1.2, 1.0), 300, 0.5, (1.0, 0.4, 0.3))

world = bpy.data.worlds.new("PreviewWorld")
world.use_nodes = True
bg = world.node_tree.nodes.get("Background")
bg.inputs[0].default_value = (0.02, 0.02, 0.03, 1.0)
bg.inputs[1].default_value = 1.0
scene.world = world

# 渲染引擎：优先 Eevee，失败回退 Workbench
for engine in ('BLENDER_EEVEE_NEXT', 'BLENDER_EEVEE', 'BLENDER_WORKBENCH'):
    try:
        scene.render.engine = engine
        break
    except TypeError:
        continue
scene.render.resolution_x = 640
scene.render.resolution_y = 640
scene.render.filepath = PREVIEW_PATH
bpy.ops.render.render(write_still=True)
print("KIMI_BLENDER_RESULT={\"preview\": \"%s\", \"engine\": \"%s\"}" % (
    PREVIEW_PATH.replace("\\", "/"), scene.render.engine))
