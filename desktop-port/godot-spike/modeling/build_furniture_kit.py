# build_furniture_kit.py — E1 可进入建筑室内家具套件烘焙（2026-09-30 机主立项：E1 内饰试点）
# 用法: blender -b --python build_furniture_kit.py
# 产物: godot/assets/models/fur_{table,chair,bed,wardrobe,sofa,tv_stand,shelf,nightstand}.glb
#       + furniture_kit_preview.png
# 件空间约定: 原点在地板面中心（z=0 落地），正面朝 -Y（glTF 导出后正面 = +Z，
#             Godot 侧 rot_y=0 时正面朝 +Z/南）。与 build_props_kit.py 的 -Y→+Z 约定一致。
# 100% 程序化生成，无外部资产。
import bpy
import math
import os
import mathutils

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", "..", ".."))
OUT_DIR = os.path.join(PROJECT_ROOT, "godot", "assets", "models")
os.makedirs(OUT_DIR, exist_ok=True)
PREVIEW_PATH = os.path.join(OUT_DIR, "furniture_kit_preview.png")

bpy.ops.wm.read_factory_settings(use_empty=True)

# ---------- 材质（具名槽位，Godot 侧可按名 override） ----------
def make_material(name, color, rough=0.9, metallic=0.0, emission=None, emission_strength=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metallic
    if emission is not None:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
        bsdf.inputs["Emission Strength"].default_value = emission_strength
    return mat

MAT_WOOD_L = make_material("wood_light", (0.55, 0.38, 0.22))
MAT_WOOD_D = make_material("wood_dark", (0.30, 0.19, 0.11))
MAT_FABRIC = make_material("fabric_blue", (0.24, 0.31, 0.42), rough=0.95)
MAT_FABRIC_L = make_material("fabric_light", (0.42, 0.48, 0.58), rough=0.95)
MAT_MATTRESS = make_material("mattress", (0.82, 0.80, 0.74), rough=0.95)
MAT_PILLOW = make_material("pillow", (0.88, 0.86, 0.80), rough=0.95)
MAT_METAL = make_material("metal", (0.25, 0.25, 0.27), rough=0.5, metallic=0.8)
MAT_SCREEN = make_material("tv_screen", (0.03, 0.04, 0.06), rough=0.35,
                           emission=(0.14, 0.20, 0.30), emission_strength=0.7)  # 待机微光
MAT_CLUTTER_R = make_material("clutter_red", (0.55, 0.18, 0.14), rough=0.85)
MAT_CLUTTER_G = make_material("clutter_green", (0.22, 0.42, 0.24), rough=0.85)
MAT_CLUTTER_Y = make_material("clutter_yellow", (0.62, 0.50, 0.20), rough=0.85)

_pieces = []  # [(name, [objs])]

def add_box(objs, name, sx, sy, sz, x, y, z, mat=MAT_WOOD_L, bevel=0.0):
    """尺寸为全尺寸，(x,y,z) 为盒中心"""
    bpy.ops.mesh.primitive_cube_add(size=1, location=(x, y, z))
    o = bpy.context.active_object
    o.name = name
    o.scale = (sx, sy, sz)
    bpy.ops.object.transform_apply(scale=True)
    if bevel > 0:
        mod = o.modifiers.new("Bevel", 'BEVEL')
        mod.width = bevel
        mod.segments = 2
        bpy.ops.object.modifier_apply(modifier=mod.name)
    o.data.materials.append(mat)
    objs.append(o)
    return o

# ---------- 1. 方桌（1.2×0.75，高 0.75） ----------
objs = []
add_box(objs, "top", 1.20, 0.75, 0.05, 0, 0, 0.725, MAT_WOOD_L, bevel=0.015)
for sx in (-1, 1):
    for sy in (-1, 1):
        add_box(objs, "leg_%d_%d" % (sx, sy), 0.06, 0.06, 0.70,
                sx * 0.54, sy * 0.30, 0.35, MAT_WOOD_D)
_pieces.append(("fur_table", objs))

# ---------- 2. 靠背椅（座面高 0.45，总高 0.90，正面 -Y） ----------
objs = []
add_box(objs, "seat", 0.42, 0.40, 0.05, 0, 0, 0.45, MAT_WOOD_L, bevel=0.01)
add_box(objs, "back", 0.42, 0.05, 0.48, 0, 0.175, 0.69, MAT_WOOD_L, bevel=0.01)
for sx in (-1, 1):
    for sy in (-1, 1):
        add_box(objs, "leg_%d_%d" % (sx, sy), 0.045, 0.045, 0.45,
                sx * 0.17, sy * 0.15, 0.225, MAT_WOOD_D)
_pieces.append(("fur_chair", objs))

# ---------- 3. 单人床（0.9×2.0，床头在 +Y，总高约 0.85） ----------
objs = []
add_box(objs, "rail_l", 0.06, 2.00, 0.25, -0.42, 0, 0.20, MAT_WOOD_D)
add_box(objs, "rail_r", 0.06, 2.00, 0.25, 0.42, 0, 0.20, MAT_WOOD_D)
add_box(objs, "headboard", 0.90, 0.06, 0.85, 0, 0.97, 0.425, MAT_WOOD_D, bevel=0.02)
add_box(objs, "footboard", 0.90, 0.06, 0.45, 0, -0.97, 0.225, MAT_WOOD_D, bevel=0.02)
add_box(objs, "slats", 0.84, 1.88, 0.06, 0, 0, 0.30, MAT_WOOD_L)
add_box(objs, "mattress", 0.84, 1.88, 0.18, 0, 0, 0.42, MAT_MATTRESS, bevel=0.03)
add_box(objs, "pillow", 0.55, 0.32, 0.12, 0, 0.70, 0.57, MAT_PILLOW, bevel=0.04)
_pieces.append(("fur_bed", objs))

# ---------- 4. 双门衣柜（1.2×0.55×2.0，正面 -Y） ----------
objs = []
add_box(objs, "body", 1.20, 0.55, 1.94, 0, 0, 0.99, MAT_WOOD_D, bevel=0.015)
add_box(objs, "cornice", 1.26, 0.60, 0.06, 0, 0, 1.99, MAT_WOOD_D, bevel=0.01)
add_box(objs, "door_l", 0.56, 0.03, 1.80, -0.29, -0.29, 0.99, MAT_WOOD_L, bevel=0.01)
add_box(objs, "door_r", 0.56, 0.03, 1.80, 0.29, -0.29, 0.99, MAT_WOOD_L, bevel=0.01)
add_box(objs, "handle_l", 0.03, 0.04, 0.18, -0.05, -0.32, 1.0, MAT_METAL)
add_box(objs, "handle_r", 0.03, 0.04, 0.18, 0.05, -0.32, 1.0, MAT_METAL)
_pieces.append(("fur_wardrobe", objs))

# ---------- 5. 双人沙发（1.6×0.75，正面 -Y，总高 0.85） ----------
objs = []
add_box(objs, "base", 1.60, 0.75, 0.30, 0, 0, 0.20, MAT_FABRIC, bevel=0.04)
add_box(objs, "back", 1.60, 0.20, 0.55, 0, 0.275, 0.575, MAT_FABRIC, bevel=0.05)
add_box(objs, "arm_l", 0.20, 0.75, 0.50, -0.70, 0, 0.50, MAT_FABRIC, bevel=0.05)
add_box(objs, "arm_r", 0.20, 0.75, 0.50, 0.70, 0, 0.50, MAT_FABRIC, bevel=0.05)
add_box(objs, "cushion_l", 0.62, 0.58, 0.15, -0.33, -0.03, 0.425, MAT_FABRIC_L, bevel=0.05)
add_box(objs, "cushion_r", 0.62, 0.58, 0.15, 0.33, -0.03, 0.425, MAT_FABRIC_L, bevel=0.05)
_pieces.append(("fur_sofa", objs))

# ---------- 6. 电视柜 + 电视机（柜 1.2×0.4×0.45，电视待机微光，总高约 1.15） ----------
objs = []
add_box(objs, "stand", 1.20, 0.40, 0.42, 0, 0, 0.21, MAT_WOOD_D, bevel=0.015)
add_box(objs, "door_l", 0.55, 0.02, 0.34, -0.29, -0.205, 0.21, MAT_WOOD_L)
add_box(objs, "door_r", 0.55, 0.02, 0.34, 0.29, -0.205, 0.21, MAT_WOOD_L)
add_box(objs, "tv_foot", 0.34, 0.16, 0.04, 0, 0.02, 0.44, MAT_METAL)
add_box(objs, "tv_panel", 1.00, 0.05, 0.58, 0, 0.02, 0.75, MAT_SCREEN, bevel=0.01)
_pieces.append(("fur_tv_stand", objs))

# ---------- 7. 置物架（0.8×0.3×1.8，四层板 + 零星杂物，正面 -Y） ----------
objs = []
add_box(objs, "side_l", 0.04, 0.30, 1.80, -0.38, 0, 0.90, MAT_WOOD_L)
add_box(objs, "side_r", 0.04, 0.30, 1.80, 0.38, 0, 0.90, MAT_WOOD_L)
for i, bz in enumerate((0.05, 0.62, 1.19, 1.76)):
    add_box(objs, "board_%d" % i, 0.72, 0.28, 0.04, 0, 0, bz, MAT_WOOD_L)
# 架上杂物（书/盒， deterministic 摆布）
add_box(objs, "books_1", 0.20, 0.18, 0.28, -0.20, 0, 0.78, MAT_CLUTTER_R)
add_box(objs, "books_2", 0.14, 0.16, 0.24, -0.02, 0, 0.76, MAT_CLUTTER_G)
add_box(objs, "box_1", 0.26, 0.22, 0.20, 0.18, 0, 1.31, MAT_CLUTTER_Y, bevel=0.02)
add_box(objs, "box_2", 0.22, 0.20, 0.16, -0.16, 0, 0.15, MAT_FABRIC_L, bevel=0.02)
_pieces.append(("fur_shelf", objs))

# ---------- 8. 床头柜（0.45×0.4×0.5，单抽屉，正面 -Y） ----------
objs = []
add_box(objs, "body", 0.45, 0.40, 0.48, 0, 0, 0.24, MAT_WOOD_D, bevel=0.012)
add_box(objs, "drawer", 0.37, 0.02, 0.16, 0, -0.205, 0.30, MAT_WOOD_L)
add_box(objs, "knob", 0.04, 0.03, 0.04, 0, -0.225, 0.30, MAT_METAL)
_pieces.append(("fur_nightstand", objs))

# ---------- 导出各件 GLB（各自合并为单 Mesh） ----------
for name, objs in _pieces:
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    bpy.context.active_object.name = name
    path = os.path.join(OUT_DIR, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB',
                              use_selection=True, export_yup=True,
                              export_apply=True, export_animations=False)
    print("KIMI_BLENDER_RESULT={\"kit\": \"%s\", \"verts\": %d}" % (
        name, len(bpy.context.active_object.data.vertices)))
    bpy.ops.object.delete()

# ---------- 合影预览 ----------
n = len(_pieces)
for i, (name, _) in enumerate(_pieces):
    path = os.path.join(OUT_DIR, name + ".glb")
    bpy.ops.import_scene.gltf(filepath=path)
    for o in bpy.context.selected_objects:
        o.location.x = (i - (n - 1) / 2.0) * 2.2

bpy.ops.mesh.primitive_plane_add(size=40, location=(0, 0, 0))
plane = bpy.context.active_object
plane.data.materials.append(make_material("ground", (0.07, 0.07, 0.08)))

bpy.ops.object.camera_add(location=(0, -14, 3.5))
cam = bpy.context.active_object
cam.data.lens = 30
d = mathutils.Vector((0, 0, 1.0)) - cam.location
cam.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
bpy.context.scene.camera = cam

bpy.ops.object.light_add(type='AREA', location=(2, -5, 6))
key = bpy.context.active_object
key.data.energy = 1000
key.data.size = 4.0
d = mathutils.Vector((0, 0, 1)) - key.location
key.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
bpy.ops.object.light_add(type='AREA', location=(-4, -2, 3))
fill = bpy.context.active_object
fill.data.energy = 500
fill.data.size = 3.0
d = mathutils.Vector((0, 0, 1)) - fill.location
fill.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()

world = bpy.data.worlds.new("W")
world.use_nodes = True
world.node_tree.nodes["Background"].inputs[0].default_value = (0.03, 0.03, 0.04, 1.0)
bpy.context.scene.world = world

scene = bpy.context.scene
for engine in ('BLENDER_EEVEE_NEXT', 'BLENDER_EEVEE', 'BLENDER_WORKBENCH'):
    try:
        scene.render.engine = engine
        break
    except TypeError:
        continue
scene.render.resolution_x = 1280
scene.render.resolution_y = 480
scene.render.filepath = PREVIEW_PATH
bpy.ops.render.render(write_still=True)
print("KIMI_BLENDER_RESULT={\"preview\": \"%s\"}" % PREVIEW_PATH.replace("\\", "/"))
