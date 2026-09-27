# build_thunder_trooper_blockout.py — 雷暴部队士兵占位白模（程序化积木人）
# 用途: 验证游戏内人形角色比例/尺寸，最终模型将由 AI 图生3D 路线替换
# 用法: blender -b --python build_thunder_trooper_blockout.py
# 产物: godot/assets/models/thunder_trooper_blockout.glb + 前后双视角预览 PNG
# 100% 程序化生成，无外部资产，无网络访问。
import bpy
import math
import os
import mathutils

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", "..", ".."))
OUT_DIR = os.path.join(PROJECT_ROOT, "godot", "assets", "models")
os.makedirs(OUT_DIR, exist_ok=True)
GLB_PATH = os.path.join(OUT_DIR, "thunder_trooper_blockout.glb")
PREVIEW_FRONT = os.path.join(OUT_DIR, "thunder_trooper_blockout_front.png")
PREVIEW_BACK = os.path.join(OUT_DIR, "thunder_trooper_blockout_back.png")

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.unit_settings.system = 'METRIC'

# ---------- 材质（白模: 统一陶灰 + 深色点缀） ----------
def make_material(name, base_color, metallic=0.0, roughness=0.8):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*base_color, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    return mat

MAT_CLAY = make_material("MAT_Clay", (0.55, 0.56, 0.58), roughness=0.75)
MAT_DARK = make_material("MAT_ClayDark", (0.16, 0.17, 0.19), roughness=0.6)

created = []

def add_box(name, size, location, mat=MAT_CLAY, bevel=0.03):
    bpy.ops.mesh.primitive_cube_add(size=1, location=location)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = (size[0], size[1], size[2])
    bpy.ops.object.transform_apply(scale=True)
    if bevel > 0:
        mod = obj.modifiers.new("Bevel", 'BEVEL')
        mod.width = bevel
        mod.segments = 3
        bpy.ops.object.modifier_apply(modifier=mod.name)
    obj.data.materials.append(mat)
    created.append(obj)
    return obj

def add_limb(name, radius, depth, location, tilt_deg=0.0, mat=MAT_CLAY):
    """圆柱四肢，tilt_deg 绕 Y 轴外撇（左正右负由调用方控制）"""
    bpy.ops.mesh.primitive_cylinder_add(radius=radius, depth=depth, vertices=20,
                                        location=location,
                                        rotation=(0, math.radians(tilt_deg), 0))
    obj = bpy.context.active_object
    obj.name = name
    obj.data.materials.append(mat)
    for poly in obj.data.polygons:
        poly.use_smooth = True
    created.append(obj)
    return obj

def add_sphere(name, radius, location, scale=(1, 1, 1), mat=MAT_CLAY):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=radius, segments=32, ring_count=16,
                                         location=location)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(scale=True)
    obj.data.materials.append(mat)
    for poly in obj.data.polygons:
        poly.use_smooth = True
    created.append(obj)
    return obj

# ---------- 人形拼装（前向 -Y，脚底 z=0，身高约 1.85m） ----------
# 靴
add_box("Boot_L", (0.13, 0.28, 0.12), (-0.11, -0.03, 0.06))
add_box("Boot_R", (0.13, 0.28, 0.12), (0.11, -0.03, 0.06))
# 小腿
add_limb("Shin_L", 0.065, 0.42, (-0.11, 0, 0.33))
add_limb("Shin_R", 0.065, 0.42, (0.11, 0, 0.33))
# 大腿
add_limb("Thigh_L", 0.085, 0.44, (-0.11, 0, 0.72))
add_limb("Thigh_R", 0.085, 0.44, (0.11, 0, 0.72))
# 骨盆
add_box("Pelvis", (0.32, 0.2, 0.2), (0, 0, 1.0))
# 躯干
add_box("Torso", (0.36, 0.22, 0.42), (0, 0, 1.3))
# 胸甲板（略前突）
add_box("ChestPlate", (0.34, 0.1, 0.28), (0, -0.13, 1.34), bevel=0.04)
# 背包
add_box("Backpack", (0.26, 0.14, 0.34), (0, 0.16, 1.32))
# 肩甲
add_sphere("ShoulderPad_L", 0.1, (-0.24, 0, 1.5), scale=(1.15, 1.0, 0.8))
add_sphere("ShoulderPad_R", 0.1, (0.24, 0, 1.5), scale=(1.15, 1.0, 0.8))
# 大臂（微外撇 A-pose）
add_limb("UpperArm_L", 0.055, 0.32, (-0.28, 0, 1.32), tilt_deg=8)
add_limb("UpperArm_R", 0.055, 0.32, (0.28, 0, 1.32), tilt_deg=-8)
# 小臂
add_limb("ForeArm_L", 0.05, 0.28, (-0.31, 0, 1.02), tilt_deg=6)
add_limb("ForeArm_R", 0.05, 0.28, (0.31, 0, 1.02), tilt_deg=-6)
# 手
add_box("Hand_L", (0.07, 0.09, 0.11), (-0.33, 0, 0.84), bevel=0.025)
add_box("Hand_R", (0.07, 0.09, 0.11), (0.33, 0, 0.84), bevel=0.025)
# 头盔（整球，盖住头部）
add_sphere("Helmet", 0.135, (0, -0.01, 1.68), scale=(1.0, 1.05, 0.95))
# 面罩（深色）
add_box("Visor", (0.15, 0.06, 0.07), (0, -0.125, 1.67), mat=MAT_DARK, bevel=0.02)
# 颈部
add_limb("Neck", 0.05, 0.08, (0, 0, 1.56))

# ---------- 合并 ----------
bpy.ops.object.select_all(action='DESELECT')
for obj in created:
    obj.select_set(True)
bpy.context.view_layer.objects.active = created[0]
bpy.ops.object.join()
trooper = bpy.context.active_object
trooper.name = "ThunderTrooper_Blockout"

# ---------- 导出 GLB ----------
bpy.ops.export_scene.gltf(filepath=GLB_PATH, export_format='GLB',
                          export_yup=True, export_apply=True, export_animations=False)
print("KIMI_BLENDER_RESULT={\"glb\": \"%s\", \"verts\": %d, \"height_m\": 1.85}" % (
    GLB_PATH.replace("\\", "/"), len(trooper.data.vertices)))

# ---------- 预览渲染（前/后双视角） ----------
bpy.ops.mesh.primitive_plane_add(size=6, location=(0, 0, 0))
plane = bpy.context.active_object
plane.data.materials.append(make_material("MAT_Ground", (0.07, 0.07, 0.08), roughness=0.9))

bpy.ops.object.camera_add(location=(2.1, -2.5, 1.6))
cam = bpy.context.active_object
scene.camera = cam

def aim(obj, target):
    d = mathutils.Vector(target) - obj.location
    obj.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()

aim(cam, (0, 0, 0.95))

def add_area(name, location, energy, size, color):
    bpy.ops.object.light_add(type='AREA', location=location)
    light = bpy.context.active_object
    light.name = name
    light.data.energy = energy
    light.data.size = size
    light.data.color = color
    aim(light, (0, 0, 1.0))

add_area("KeyLight", (1.6, -1.4, 2.6), 500, 1.0, (1.0, 0.95, 0.9))
add_area("FillLight", (-1.8, -1.0, 1.4), 250, 0.8, (0.75, 0.85, 1.0))
add_area("RimLight", (0.4, 1.8, 2.2), 400, 0.7, (1.0, 0.5, 0.35))

world = bpy.data.worlds.new("PreviewWorld")
world.use_nodes = True
world.node_tree.nodes["Background"].inputs[0].default_value = (0.02, 0.02, 0.03, 1.0)
scene.world = world

for engine in ('BLENDER_EEVEE_NEXT', 'BLENDER_EEVEE', 'BLENDER_WORKBENCH'):
    try:
        scene.render.engine = engine
        break
    except TypeError:
        continue
scene.render.resolution_x = 640
scene.render.resolution_y = 640

scene.render.filepath = PREVIEW_FRONT
bpy.ops.render.render(write_still=True)

cam.location = (-2.1, 2.5, 1.6)
aim(cam, (0, 0, 0.95))
scene.render.filepath = PREVIEW_BACK
bpy.ops.render.render(write_still=True)

print("KIMI_BLENDER_RESULT={\"previews\": [\"%s\", \"%s\"], \"engine\": \"%s\"}" % (
    PREVIEW_FRONT.replace("\\", "/"), PREVIEW_BACK.replace("\\", "/"), scene.render.engine))
