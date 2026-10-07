# build_interior_props.py — 道具批2：拾取件 + 「画皮居所」室内细节件烘焙（2026-10-07 机主裁决）
# 用法: blender -b --python build_interior_props.py
# 产物: godot/assets/models/{pickup_battery,pickup_medkit,pickup_intel,
#       dec_tableware,dec_mug,dec_helmet,dec_slippers,dec_roster,dec_jacket}.glb
#       + interior_props_preview.png
# 件空间约定: 原点在放置面中心（z=0 落面），正面朝 -Y（glTF 导出后 = +Z）。
# 墙贴类（roster/jacket）: 原点在件底边中心，背面 z=0 贴墙，件向 -Y 凸出。
# 100% 程序化生成，无外部资产。
import bpy
import math
import os
import mathutils

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", "..", ".."))
OUT_DIR = os.path.join(PROJECT_ROOT, "godot", "assets", "models")
os.makedirs(OUT_DIR, exist_ok=True)
PREVIEW_PATH = os.path.join(OUT_DIR, "interior_props_preview.png")

bpy.ops.wm.read_factory_settings(use_empty=True)

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

MAT_DARK = make_material("device_dark", (0.10, 0.10, 0.12), rough=0.5, metallic=0.4)
MAT_CELL = make_material("cell_glow", (0.15, 0.35, 0.60), rough=0.4,
                         emission=(0.25, 0.55, 1.0), emission_strength=2.2)  # 电池组蓝色冷光
MAT_MED_WHITE = make_material("med_white", (0.85, 0.85, 0.82), rough=0.6)
MAT_MED_RED = make_material("med_red", (0.72, 0.10, 0.08), rough=0.6,
                            emission=(0.55, 0.06, 0.04), emission_strength=0.8)
MAT_SCREEN_G = make_material("intel_screen", (0.04, 0.10, 0.06), rough=0.3,
                             emission=(0.20, 0.85, 0.45), emission_strength=1.6)  # 取证终端绿屏
MAT_CHINA = make_material("china_white", (0.88, 0.87, 0.82), rough=0.35)  # 瓷
MAT_WOOD = make_material("chopstick_wood", (0.45, 0.30, 0.16), rough=0.85)
MAT_ENAMEL = make_material("enamel_white", (0.82, 0.84, 0.80), rough=0.35)  # 搪瓷
MAT_RIM = make_material("enamel_rim_blue", (0.12, 0.25, 0.45), rough=0.4)
MAT_HELMET = make_material("helmet_yellow", (0.85, 0.62, 0.08), rough=0.45)
MAT_PLASTIC = make_material("slipper_blue", (0.15, 0.30, 0.55), rough=0.8)
MAT_PAPER = make_material("paper_white", (0.80, 0.78, 0.70), rough=0.95)
MAT_INK = make_material("ink_dark", (0.08, 0.08, 0.08), rough=0.95)
MAT_JACKET = make_material("jacket_orange", (0.72, 0.32, 0.08), rough=0.9)  # 工地工装橙
MAT_METAL = make_material("metal", (0.30, 0.30, 0.32), rough=0.5, metallic=0.8)

_pieces = []

def add_box(objs, name, sx, sy, sz, x, y, z, mat=MAT_DARK, bevel=0.0):
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

def add_cyl(objs, name, radius, depth, x, y, z, mat=MAT_DARK, rotation=(0, 0, 0), verts=12):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=depth,
                                        location=(x, y, z), rotation=rotation)
    o = bpy.context.active_object
    o.name = name
    o.data.materials.append(mat)
    objs.append(o)
    return o

# ---------- 拾取 1. E 系列电池组（0.24×0.12×0.16，顶部蓝色冷光条） ----------
objs = []
add_box(objs, "body", 0.24, 0.12, 0.13, 0, 0, 0.065, MAT_DARK, bevel=0.015)
add_box(objs, "cell_strip", 0.20, 0.10, 0.03, 0, 0, 0.145, MAT_CELL, bevel=0.008)
add_box(objs, "contact_l", 0.03, 0.05, 0.02, -0.07, -0.045, 0.02, MAT_METAL)
add_box(objs, "contact_r", 0.03, 0.05, 0.02, 0.07, -0.045, 0.02, MAT_METAL)
_pieces.append(("pickup_battery", objs))

# ---------- 拾取 2. 医疗注射包（0.28×0.14×0.20 白盒红十字） ----------
objs = []
add_box(objs, "case", 0.28, 0.14, 0.20, 0, 0, 0.10, MAT_MED_WHITE, bevel=0.02)
add_box(objs, "cross_h", 0.14, 0.012, 0.045, 0, -0.075, 0.12, MAT_MED_RED)
add_box(objs, "cross_v", 0.045, 0.012, 0.14, 0, -0.075, 0.12, MAT_MED_RED)
add_box(objs, "latch", 0.06, 0.03, 0.03, 0, -0.075, 0.20, MAT_METAL)
_pieces.append(("pickup_medkit", objs))

# ---------- 拾取 3. 取证终端（0.16×0.03×0.24 手持终端，绿屏） ----------
objs = []
add_box(objs, "slab", 0.16, 0.03, 0.24, 0, 0, 0.12, MAT_DARK, bevel=0.01)
add_box(objs, "screen", 0.12, 0.008, 0.16, 0, -0.018, 0.14, MAT_SCREEN_G)
add_box(objs, "btn", 0.04, 0.008, 0.02, 0, -0.018, 0.035, MAT_METAL)
_pieces.append(("pickup_intel", objs))

# ---------- 细节 4. 碗筷碟组（双人份，摆在 0.5×0.4 范围；原点在桌面） ----------
objs = []
for sx in (-1, 1):
    bx = sx * 0.14
    add_cyl(objs, "bowl_%d" % sx, 0.055, 0.05, bx, 0.08, 0.025, MAT_CHINA, verts=14)
    add_cyl(objs, "plate_%d" % sx, 0.08, 0.015, bx, -0.08, 0.008, MAT_CHINA, verts=14)
    # 筷子一双（细方棍，斜搁在碟边）
    add_box(objs, "chop_%da" % sx, 0.008, 0.22, 0.008, bx + 0.06, -0.02, 0.02,
            MAT_WOOD, bevel=0.002)
    add_box(objs, "chop_%db" % sx, 0.008, 0.22, 0.008, bx + 0.075, -0.02, 0.02,
            MAT_WOOD, bevel=0.002)
_pieces.append(("dec_tableware", objs))

# ---------- 细节 5. 搪瓷杯（白身蓝边 + 把手） ----------
objs = []
add_cyl(objs, "cup", 0.045, 0.10, 0, 0, 0.05, MAT_ENAMEL, verts=14)
add_cyl(objs, "rim", 0.047, 0.012, 0, 0, 0.096, MAT_RIM, verts=14)
add_box(objs, "handle", 0.012, 0.045, 0.05, 0.055, 0, 0.055, MAT_ENAMEL, bevel=0.004)
_pieces.append(("dec_mug", objs))

# ---------- 细节 6. 安全帽（半球壳 + 帽檐） ----------
objs = []
bpy.ops.mesh.primitive_uv_sphere_add(radius=0.11, segments=16, ring_count=8, location=(0, 0, 0.02))
dome = bpy.context.active_object
dome.name = "dome"
dome.scale = (1.0, 1.0, 0.75)
bpy.ops.object.transform_apply(scale=True)
dome.data.materials.append(MAT_HELMET)
objs.append(dome)
add_cyl(objs, "brim", 0.13, 0.015, 0, 0, 0.025, MAT_HELMET, verts=16)
_pieces.append(("dec_helmet", objs))

# ---------- 细节 7. 人字拖一对（鞋尖朝 +Y；摆放时靠 rot 控制朝向） ----------
objs = []
for sx in (-1, 1):
    x = sx * 0.06
    add_box(objs, "sole_%d" % sx, 0.09, 0.26, 0.02, x, 0, 0.01, MAT_PLASTIC, bevel=0.02)
    add_box(objs, "strap_%d" % sx, 0.015, 0.12, 0.015, x, 0.03, 0.035, MAT_PLASTIC, bevel=0.005)
_pieces.append(("dec_slippers", objs))

# ---------- 细节 8. 轮值表墙贴（0.4×0.56 竖版，背面 z=0 贴墙；表格线） ----------
objs = []
add_box(objs, "paper", 0.40, 0.012, 0.56, 0, -0.006, 0.28, MAT_PAPER)
add_box(objs, "title_bar", 0.34, 0.004, 0.05, 0, -0.014, 0.50, MAT_INK)
for i in range(6):
    add_box(objs, "row_%d" % i, 0.34, 0.004, 0.012, 0, -0.014, 0.40 - i * 0.06, MAT_INK)
_pieces.append(("dec_roster", objs))

# ---------- 细节 9. 挂墙工作服（工地工装：衣身+双袖+挂钩，背面 z=0 贴墙） ----------
objs = []
add_box(objs, "torso", 0.42, 0.10, 0.55, 0, -0.05, 0.45, MAT_JACKET, bevel=0.03)
add_box(objs, "sleeve_l", 0.11, 0.09, 0.42, -0.26, -0.05, 0.50, MAT_JACKET, bevel=0.025)
add_box(objs, "sleeve_r", 0.11, 0.09, 0.42, 0.26, -0.05, 0.50, MAT_JACKET, bevel=0.025)
add_box(objs, "collar", 0.20, 0.06, 0.08, 0, -0.06, 0.75, MAT_JACKET, bevel=0.015)
add_cyl(objs, "hook", 0.015, 0.10, 0, -0.03, 0.86, MAT_METAL,
        rotation=(math.radians(90), 0, 0), verts=8)
_pieces.append(("dec_jacket", objs))

# ---------- 导出各件 GLB ----------
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
        o.location.x = (i - (n - 1) / 2.0) * 0.9

bpy.ops.mesh.primitive_plane_add(size=20, location=(0, 0, 0))
plane = bpy.context.active_object
plane.data.materials.append(make_material("ground", (0.07, 0.07, 0.08)))

bpy.ops.object.camera_add(location=(0, -5.5, 1.6))
cam = bpy.context.active_object
cam.data.lens = 35
d = mathutils.Vector((0, 0, 0.35)) - cam.location
cam.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
bpy.context.scene.camera = cam

bpy.ops.object.light_add(type='AREA', location=(1, -3, 4))
key = bpy.context.active_object
key.data.energy = 600
key.data.size = 3.0
d = mathutils.Vector((0, 0, 0.3)) - key.location
key.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
bpy.ops.object.light_add(type='AREA', location=(-2, -1, 2))
fill = bpy.context.active_object
fill.data.energy = 300
fill.data.size = 2.0
d = mathutils.Vector((0, 0, 0.3)) - fill.location
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
