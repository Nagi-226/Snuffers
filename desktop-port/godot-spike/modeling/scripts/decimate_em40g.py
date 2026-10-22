## decimate_em40g.py — EM-40G 榴弹减面（2026-10-22）
## 147 万三角面（AI 图生原始密度）→ ~3000（投射物一晃而过，贴图承担观感）。
## 输入输出同文件：em40g_grenade_game.glb（几何已归一化，本步只减面不改变换/贴图）。
import bpy
import math
import os

DST = r"E:\Github Project\Nagi_Games\Snuffers\desktop-port\godot-spike\modeling\em-weapons\em40g_grenade_game.glb"
TARGET_TRIS = 3000

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=DST)

for o in bpy.data.objects:
    if o.type != "MESH":
        continue
    o.data.calc_loop_triangles()
    before = len(o.data.loop_triangles)
    mod = o.modifiers.new("Decimate", "DECIMATE")
    mod.ratio = min(1.0, TARGET_TRIS / max(1, before))
    mod.use_collapse_triangulate = True
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.modifier_apply(modifier=mod.name)
    o.data.calc_loop_triangles()
    print("DECIMATED", o.name, before, "->", len(o.data.loop_triangles))

# 减面后侧视复渲（确认外观未崩）
scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 640
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
cam.location = (0.5, 0.0, 0.0)
cam.rotation_euler = (math.radians(90), 0, math.radians(90))
scene.render.filepath = r"E:\Github Project\Nagi_Games\Snuffers\desktop-port\godot-spike\modeling\em-weapons\em40g_game_side_decim.png"
bpy.ops.render.render(write_still=True)

bpy.ops.export_scene.gltf(filepath=DST, export_format="GLB", export_yup=True)
print("EXPORTED:", DST, os.path.getsize(DST), "bytes")
