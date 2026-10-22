## scale_check_em40g.py — 榴弹 vs EM-68A 尺寸对比渲染（2026-10-22）
## 榴弹全长 0.20m 放在步枪旁渲染，人工核对 40mm 榴弹与步枪的比例观感。
import bpy
import math
import mathutils
import os

RIFLE = r"E:\Github Project\Nagi_Games\Snuffers\godot\assets\models\weapons\em68a_viewmodel.glb"
GRENADE = r"E:\Github Project\Nagi_Games\Snuffers\desktop-port\godot-spike\modeling\em-weapons\em40g_grenade_game.glb"
OUT = r"E:\Github Project\Nagi_Games\Snuffers\desktop-port\godot-spike\modeling\em-weapons\em40g_scale_check.png"

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=RIFLE)
rifle_objs = [o for o in bpy.data.objects if o.type == "MESH"]


def bbox(objs):
    min_v = mathutils.Vector((1e18, 1e18, 1e18))
    max_v = mathutils.Vector((-1e18, -1e18, -1e18))
    for o in objs:
        for corner in o.bound_box:
            w = o.matrix_world @ mathutils.Vector(corner)
            min_v = mathutils.Vector(map(min, min_v, w))
            max_v = mathutils.Vector(map(max, max_v, w))
    return min_v, max_v


rmin, rmax = bbox(rifle_objs)
rdims = rmax - rmin
print("RIFLE dims =", tuple(round(d, 3) for d in rdims))

# 步枪归位：质心到原点（仅视觉对齐用，不改文件）
roffset = -(rmin + rmax) / 2.0
for o in bpy.data.objects:
    if o.parent is None:
        o.location += roffset

existing = set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=GRENADE)
grenade_objs = [o for o in bpy.data.objects if o not in existing and o.type == "MESH"]
gmin, gmax = bbox(grenade_objs)
gdims = gmax - gmin
print("GRENADE dims =", tuple(round(d, 4) for d in gdims))

# 榴弹挂到步枪前下方（护木下挂位，仅视觉对比）
glen = max(gdims.x, gdims.y, gdims.z)
for o in grenade_objs:
    if o.parent is None:
        # 弹轴在 Blender Y；放到枪管（假设枪管沿 -Y 前方）下方
        o.location += mathutils.Vector((0.0, -rdims.y * 0.28, -rdims.z * 0.5 - 0.06))

scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 960
scene.render.resolution_y = 640
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
cam.location = (1.6, 0.0, 0.0)
cam.rotation_euler = (math.radians(90), 0, math.radians(90))
scene.render.filepath = OUT
bpy.ops.render.render(write_still=True)
print("RENDERED:", OUT)
