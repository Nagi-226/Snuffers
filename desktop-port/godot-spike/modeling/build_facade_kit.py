# build_facade_kit.py — 模块化立面套件烘焙（借鉴 Claude-of-Duty kit.js panel space 约定）
# 用法: blender -b --python build_facade_kit.py
# 产物: godot/assets/models/kit_{wall,window,door,balcony}.glb + kit_preview.png
# panel space: x 沿墙居中，z 从地板线向上，y=0 为外墙面、墙厚向 +Y 内侧延伸。
# （glTF 导出后: 前面在 z=0，墙身向 -Z 内侧，outward normal = +Z）
# 100% 程序化生成，无外部资产。
import bpy
import math
import os
import mathutils

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", "..", ".."))
OUT_DIR = os.path.join(PROJECT_ROOT, "godot", "assets", "models")
os.makedirs(OUT_DIR, exist_ok=True)
PREVIEW_PATH = os.path.join(OUT_DIR, "kit_preview.png")

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
MAT_WOOD = make_material("wood", (0.35, 0.22, 0.12))
MAT_GLASS = make_material("glass", (0.05, 0.07, 0.10), rough=0.55)
MAT_METAL = make_material("metal", (0.22, 0.22, 0.24), rough=0.5, metallic=0.8)

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

# ---------- 1. 素墙板 ----------
objs = []
add_box(objs, "wall", BAY_W, WALL_T, FLOOR_H, 0, WALL_T / 2, FLOOR_H / 2)
_pieces.append(("kit_wall", objs))

# ---------- 2. 窗单元（1.2×1.5 窗洞，窗台高 0.9，含窗框/窗台板/玻璃） ----------
objs = []
WIN_W, WIN_H, SILL_H = 1.2, 1.5, 0.9
xw = WIN_W / 2  # 0.6
z_top = SILL_H + WIN_H  # 2.4
add_box(objs, "w_left", (BAY_W / 2 - xw), WALL_T, FLOOR_H, -(xw + (BAY_W / 2 - xw) / 2), WALL_T / 2, FLOOR_H / 2)
add_box(objs, "w_right", (BAY_W / 2 - xw), WALL_T, FLOOR_H, (xw + (BAY_W / 2 - xw) / 2), WALL_T / 2, FLOOR_H / 2)
add_box(objs, "w_bottom", WIN_W, WALL_T, SILL_H, 0, WALL_T / 2, SILL_H / 2)
add_box(objs, "w_top", WIN_W, WALL_T, FLOOR_H - z_top, 0, WALL_T / 2, (z_top + FLOOR_H) / 2)
# 窗框（凸出墙面 0.03）
fw = 0.06
add_box(objs, "f_l", fw, WALL_T + 0.06, WIN_H + fw * 2, -xw - fw / 2 + 0.01, (WALL_T) / 2 - 0.03, (SILL_H + z_top) / 2, MAT_WOOD)
add_box(objs, "f_r", fw, WALL_T + 0.06, WIN_H + fw * 2, xw + fw / 2 - 0.01, (WALL_T) / 2 - 0.03, (SILL_H + z_top) / 2, MAT_WOOD)
add_box(objs, "f_t", WIN_W, WALL_T + 0.06, fw, 0, (WALL_T) / 2 - 0.03, z_top + fw / 2 - 0.01, MAT_WOOD)
# 窗台板（外挑）
add_box(objs, "sill", WIN_W + 0.2, WALL_T + 0.16, 0.07, 0, WALL_T / 2 - 0.06, SILL_H - 0.035, MAT_PLASTER, bevel=0.015)
# 玻璃（内退 0.10）
add_box(objs, "glass", WIN_W - 0.04, 0.02, WIN_H - 0.04, 0, WALL_T - 0.10, (SILL_H + z_top) / 2, MAT_GLASS)
_pieces.append(("kit_window", objs))

# ---------- 3. 门单元（1.0×2.2 门洞，含门框/门槛/门板） ----------
objs = []
DOOR_W, DOOR_H = 1.0, 2.2
dw = DOOR_W / 2
add_box(objs, "d_left", (BAY_W / 2 - dw), WALL_T, FLOOR_H, -(dw + (BAY_W / 2 - dw) / 2), WALL_T / 2, FLOOR_H / 2)
add_box(objs, "d_right", (BAY_W / 2 - dw), WALL_T, FLOOR_H, (dw + (BAY_W / 2 - dw) / 2), WALL_T / 2, FLOOR_H / 2)
add_box(objs, "d_top", DOOR_W, WALL_T, FLOOR_H - DOOR_H, 0, WALL_T / 2, (DOOR_H + FLOOR_H) / 2)
add_box(objs, "df_l", fw, WALL_T + 0.06, DOOR_H, -dw - fw / 2 + 0.01, WALL_T / 2 - 0.03, DOOR_H / 2, MAT_WOOD)
add_box(objs, "df_r", fw, WALL_T + 0.06, DOOR_H, dw + fw / 2 - 0.01, WALL_T / 2 - 0.03, DOOR_H / 2, MAT_WOOD)
add_box(objs, "df_t", DOOR_W, WALL_T + 0.06, fw, 0, WALL_T / 2 - 0.03, DOOR_H + fw / 2 - 0.01, MAT_WOOD)
# 门槛石（外挑半步）
add_box(objs, "threshold", DOOR_W + 0.3, WALL_T + 0.3, 0.09, 0, WALL_T / 2 - 0.12, 0.045, MAT_PLASTER, bevel=0.02)
# 门板（内退 0.12，木）
add_box(objs, "door", DOOR_W - 0.06, 0.05, DOOR_H - 0.06, 0, WALL_T - 0.12, DOOR_H / 2, MAT_WOOD, bevel=0.015)
_pieces.append(("kit_door", objs))

# ---------- 4. 阳台单元（落地门窗洞 + 外挑 0.9m 板 + 铁栏杆） ----------
objs = []
BD_W, BD_H = 0.9, 2.1
bw = BD_W / 2
add_box(objs, "b_left", (BAY_W / 2 - bw), WALL_T, FLOOR_H, -(bw + (BAY_W / 2 - bw) / 2), WALL_T / 2, FLOOR_H / 2)
add_box(objs, "b_right", (BAY_W / 2 - bw), WALL_T, FLOOR_H, (bw + (BAY_W / 2 - bw) / 2), WALL_T / 2, FLOOR_H / 2)
add_box(objs, "b_top", BD_W, WALL_T, FLOOR_H - BD_H, 0, WALL_T / 2, (BD_H + FLOOR_H) / 2)
# 玻璃门（内退）
add_box(objs, "b_glass", BD_W - 0.04, 0.02, BD_H - 0.04, 0, WALL_T - 0.08, BD_H / 2, MAT_GLASS)
# 阳台板（外墙面 y=0 向外 -Y 挑 0.9）
SLAB_D = 0.9
add_box(objs, "slab", 2.2, SLAB_D + WALL_T, 0.14, 0, -SLAB_D / 2 + WALL_T / 2, 0.07, MAT_PLASTER, bevel=0.02)
# 栏杆：顶扶手 + 竖杆
add_box(objs, "rail_top", 2.2, 0.05, 0.05, 0, -SLAB_D + WALL_T / 2 + 0.02, 1.05, MAT_METAL)
for i in range(9):
    x = -1.05 + i * (2.1 / 8)
    add_box(objs, "rail_v%d" % i, 0.03, 0.03, 0.95, x, -SLAB_D + WALL_T / 2 + 0.02, 0.55, MAT_METAL)
# 侧栏杆
for side in (-1, 1):
    add_box(objs, "rail_side%d" % side, 0.05, SLAB_D, 0.05, side * 1.08, -SLAB_D / 2 + WALL_T / 2, 1.05, MAT_METAL)
_pieces.append(("kit_balcony", objs))

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
        o.location.x = (i - 1.5) * 3.5

bpy.ops.mesh.primitive_plane_add(size=30, location=(0, 0, 0))
plane = bpy.context.active_object
plane.data.materials.append(make_material("ground", (0.07, 0.07, 0.08)))

bpy.ops.object.camera_add(location=(0, -14, 3.4))
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
scene.render.resolution_x = 960
scene.render.resolution_y = 480
scene.render.filepath = PREVIEW_PATH
bpy.ops.render.render(write_still=True)
print("KIMI_BLENDER_RESULT={\"preview\": \"%s\"}" % PREVIEW_PATH.replace("\\", "/"))
