## normalize_em40g.py — EM-40G 榴弹 GLB 归一化 v2（2026-10-22）
## 目标：全长 0.20m、弹轴对齐 Blender Y（导出 glTF 后 = Z 轴）、质心原点、贴图 512²。
## 渲染两张正交验证图（+X 侧视 / +Z 顶视），供人工确认弹头朝向；
## 若弹头朝 -Y（导出后 +Z， backwards），设 FLIP=True 重跑即可。
import bpy
import math
import mathutils
import os

SRC = r"E:\Github Project\Nagi_Games\Snuffers\desktop-port\godot-spike\modeling\em-weapons\em40g_grenade.glb"
DST = r"E:\Github Project\Nagi_Games\Snuffers\desktop-port\godot-spike\modeling\em-weapons\em40g_grenade_game.glb"
TARGET_LENGTH = 0.20  # m
FLIP = False  # 弹头朝 -Y 时改 True 重跑

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)

meshes = [o for o in bpy.data.objects if o.type == "MESH"]
assert meshes, "no mesh objects imported"


def world_bbox():
    min_v = mathutils.Vector((1e18, 1e18, 1e18))
    max_v = mathutils.Vector((-1e18, -1e18, -1e18))
    for o in meshes:
        for corner in o.bound_box:
            w = o.matrix_world @ mathutils.Vector(corner)
            min_v = mathutils.Vector(map(min, min_v, w))
            max_v = mathutils.Vector(map(max, max_v, w))
    return min_v, max_v


min_v, max_v = world_bbox()
dims = max_v - min_v
print("IMPORT dims (x,y,z) =", tuple(round(d, 4) for d in dims))

root = bpy.data.objects.new("EM40G_Root", None)
bpy.context.collection.objects.link(root)
for o in bpy.data.objects:
    if o != root and o.parent is None:
        o.parent = root

# 弹轴（最长轴）归一到 Blender Y
if dims.x >= dims.y and dims.x >= dims.z:
    root.rotation_euler.rotate_axis("Z", math.radians(90.0))   # X -> Y
elif dims.z >= dims.x and dims.z >= dims.y:
    root.rotation_euler.rotate_axis("X", math.radians(-90.0))  # Z -> Y
bpy.context.view_layer.update()

if FLIP:
    root.rotation_euler.rotate_axis("X", math.radians(180.0))  # +Y <-> -Y
    bpy.context.view_layer.update()

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
bpy.context.view_layer.update()

min_v, max_v = world_bbox()
dims = max_v - min_v
center = (min_v + max_v) / 2.0
length = max(dims.x, dims.y, dims.z)
scale = TARGET_LENGTH / length
print("POST-ROT dims =", tuple(round(d, 4) for d in dims), "scale =", round(scale, 5))

root.location = -center * scale
root.scale = (scale, scale, scale)
bpy.context.view_layer.update()
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

min_v, max_v = world_bbox()
dims = max_v - min_v
print("FINAL dims =", tuple(round(d, 5) for d in dims))
print("FINAL min =", tuple(round(v, 5) for v in min_v), "max =", tuple(round(v, 5) for v in max_v))

for img in bpy.data.images:
    if img.size[0] > 512:
        img.scale(512, max(1, int(img.size[1] * 512 / img.size[0])))
print("images:", [(i.name, tuple(i.size)) for i in bpy.data.images])

# 验证渲染：引擎用 4.1 的 BLENDER_EEVEE
scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 640
scene.render.resolution_y = 640
scene.render.film_transparent = False
world = bpy.data.worlds.new("W")
scene.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs[0].default_value = (0.7, 0.7, 0.7, 1.0)

light_data = bpy.data.lights.new("Sun", type="SUN")
light_data.energy = 4.0
light = bpy.data.objects.new("Sun", light_data)
bpy.context.collection.objects.link(light)
light.rotation_euler = (math.radians(50), math.radians(15), 0)

cam_data = bpy.data.cameras.new("Cam")
cam = bpy.data.objects.new("Cam", cam_data)
bpy.context.collection.objects.link(cam)
scene.camera = cam

# 侧视：相机在 +X 看向原点 → 画面横轴 = Blender Y（弹轴）
cam.location = (0.5, 0.0, 0.0)
cam.rotation_euler = (math.radians(90), 0, math.radians(90))
scene.render.filepath = r"E:\Github Project\Nagi_Games\Snuffers\desktop-port\godot-spike\modeling\em-weapons\em40g_game_side.png"
bpy.ops.render.render(write_still=True)

bpy.ops.export_scene.gltf(filepath=DST, export_format="GLB", export_yup=True)
print("EXPORTED:", DST, os.path.getsize(DST), "bytes")
