# build_props_kit.py — 城中村道具套件烘焙（借鉴 Claude-of-Duty props.js/kit.js）
# 用法: blender -b --python build_props_kit.py
# 产物: godot/assets/models/kit_{shopfront,ac_unit,drainpipe}.glb + props_kit_preview.png
# panel space 与 build_facade_kit.py 一致: 前面(贴墙面) z=0、件向外(-Y)凸出、原点在地板线。
# （glTF 导出后: 贴墙面在 z=0，凸出方向 = +Z，outward normal = +Z）
# 100% 程序化生成，无外部资产。
import bpy
import math
import os
import mathutils

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", "..", ".."))
OUT_DIR = os.path.join(PROJECT_ROOT, "godot", "assets", "models")
os.makedirs(OUT_DIR, exist_ok=True)
PREVIEW_PATH = os.path.join(OUT_DIR, "props_kit_preview.png")

BAY_W = 3.0     # 开间宽
FLOOR_H = 3.0   # 层高
WALL_T = 0.25   # 墙厚

bpy.ops.wm.read_factory_settings(use_empty=True)

# ---------- 材质（具名槽位，Godot 侧可按名 override） ----------
def make_material(name, color, rough=0.9, metallic=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metallic
    return mat

MAT_PLASTER = make_material("plaster", (0.78, 0.73, 0.63))
MAT_SHUTTER = make_material("shutter_metal", (0.30, 0.31, 0.33), rough=0.55, metallic=0.7)
MAT_METAL = make_material("metal", (0.22, 0.22, 0.24), rough=0.5, metallic=0.8)
MAT_SIGN = make_material("signage", (0.62, 0.30, 0.16), rough=0.8)  # 招牌底色（城中村暖色店招）
MAT_DARK = make_material("dark_grille", (0.06, 0.06, 0.07), rough=0.7)

_pieces = []  # [(name, [objs])]

def add_box(objs, name, sx, sy, sz, x, y, z, mat=MAT_PLASTER, bevel=0.0):
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

def add_cylinder(objs, name, radius, depth, x, y, z, mat=MAT_METAL, rotation=(0, 0, 0), verts=10):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=depth,
                                        location=(x, y, z), rotation=rotation)
    o = bpy.context.active_object
    o.name = name
    o.data.materials.append(mat)
    objs.append(o)
    return o

# ---------- 1. 卷帘门商铺单元（一层开间：门柱 + 卷帘门 + 门楣招牌） ----------
objs = []
COL_W = 0.30
# 两侧门柱
add_box(objs, "col_l", COL_W, WALL_T, FLOOR_H, -(BAY_W / 2 - COL_W / 2), WALL_T / 2, FLOOR_H / 2)
add_box(objs, "col_r", COL_W, WALL_T, FLOOR_H, (BAY_W / 2 - COL_W / 2), WALL_T / 2, FLOOR_H / 2)
# 门楣墙带（招牌背后，z 2.4 以上）
add_box(objs, "lintel", BAY_W - COL_W * 2, WALL_T, FLOOR_H - 2.4, 0, WALL_T / 2, (2.4 + FLOOR_H) / 2)
# 卷帘门：7 片横向波纹板，内退 0.06
SHUT_W = BAY_W - COL_W * 2 - 0.06
for i in range(7):
    slat_h = 2.4 / 7
    add_box(objs, "slat_%d" % i, SHUT_W, 0.05, slat_h - 0.025, 0, WALL_T - 0.06,
            (i + 0.5) * slat_h, MAT_SHUTTER)
# 门楣招牌（外挑 0.22，城中村店招）
add_box(objs, "sign", BAY_W - 0.3, 0.22, 0.62, 0, -0.11 + 0.0, 2.72, MAT_SIGN, bevel=0.02)
# 门口踏步
add_box(objs, "step", SHUT_W, 0.5, 0.14, 0, -0.25 + WALL_T / 2, 0.07, MAT_PLASTER, bevel=0.02)
_pieces.append(("kit_shopfront", objs))

# ---------- 2. 空调外机（贴墙 y=0 向外 -Y 凸出，原点在安装底面） ----------
objs = []
AC_W, AC_H, AC_D = 0.80, 0.55, 0.30
# 外机壳
add_box(objs, "body", AC_W, AC_D, AC_H, 0, -AC_D / 2, AC_H / 2 + 0.08, MAT_METAL, bevel=0.02)
# 正面风扇格栅（深色圆盘）
add_cylinder(objs, "fan", 0.20, 0.03, 0, -AC_D - 0.015, AC_H / 2 + 0.08, MAT_DARK,
             rotation=(math.radians(90), 0, 0), verts=16)
# 支架两条腿（斜撑简化成小方柱）
for side in (-1, 1):
    add_box(objs, "leg_%d" % side, 0.05, AC_D * 0.8, 0.06, side * AC_W * 0.32,
            -AC_D * 0.4, 0.03, MAT_METAL)
_pieces.append(("kit_ac_unit", objs))

# ---------- 3. 排水管（3m 竖管 + 两道抱箍 + 底部弯头，贴面 y=0，管心外凸 0.07） ----------
objs = []
PIPE_R = 0.05
add_cylinder(objs, "pipe", PIPE_R, FLOOR_H, 0, -0.07, FLOOR_H / 2, MAT_METAL)
for bz in (1.0, 2.0):
    add_box(objs, "band_%.1f" % bz, 0.14, 0.10, 0.06, 0, -0.07, bz, MAT_METAL)
# 底部出水弯（45° 短管）
add_cylinder(objs, "elbow", PIPE_R, 0.25, 0, -0.15, 0.12, MAT_METAL,
             rotation=(math.radians(45), 0, 0))
_pieces.append(("kit_drainpipe", objs))

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
for i, (name, _) in enumerate(_pieces):
    path = os.path.join(OUT_DIR, name + ".glb")
    bpy.ops.import_scene.gltf(filepath=path)
    for o in bpy.context.selected_objects:
        o.location.x = (i - 1) * 4.0

bpy.ops.mesh.primitive_plane_add(size=30, location=(0, 0, 0))
plane = bpy.context.active_object
plane.data.materials.append(make_material("ground", (0.07, 0.07, 0.08)))

bpy.ops.object.camera_add(location=(0, -13, 3.2))
cam = bpy.context.active_object
cam.data.lens = 32
d = mathutils.Vector((0, 0, 1.2)) - cam.location
cam.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
bpy.context.scene.camera = cam

bpy.ops.object.light_add(type='AREA', location=(2, -4, 6))
key = bpy.context.active_object
key.data.energy = 800
key.data.size = 3.0
d = mathutils.Vector((0, 0, 1)) - key.location
key.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
bpy.ops.object.light_add(type='AREA', location=(-3, -2, 3))
fill = bpy.context.active_object
fill.data.energy = 400
fill.data.size = 2.0
d = mathutils.Vector((0, 0, 1)) - fill.location
fill.rotation_euler = d.to_track_quat('-Y' if False else '-Z', 'Y').to_euler()

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
scene.render.resolution_x = 960
scene.render.resolution_y = 480
scene.render.filepath = PREVIEW_PATH
bpy.ops.render.render(write_still=True)
print("KIMI_BLENDER_RESULT={\"preview\": \"%s\"}" % PREVIEW_PATH.replace("\\", "/"))
