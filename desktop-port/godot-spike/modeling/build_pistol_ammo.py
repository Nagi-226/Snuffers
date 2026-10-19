# build_pistol_ammo.py — 手枪弹匣组拾取件烘焙（2026-10-19 机主立项：两种弹药道具视觉区分）
# 用法: blender -b --python build_pistol_ammo.py
# 产物: godot/assets/models/pickup_pistol_ammo.glb
# 件空间约定: 原点在放置面中心（z=0 落面），正面朝 -Y（glTF 导出后 = +Z）。
# 设计：立式三联弹匣排（区别于电池组的扁平蓝盒）——无托手枪弹匣宽短，琥珀色电量窗。
# 100% 程序化生成，无外部资产。
import bpy
import os

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", "..", ".."))
OUT_DIR = os.path.join(PROJECT_ROOT, "godot", "assets", "models")
os.makedirs(OUT_DIR, exist_ok=True)

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

MAT_DARK = make_material("mag_dark", (0.09, 0.09, 0.11), rough=0.5, metallic=0.4)
MAT_AMBER = make_material("charge_amber", (0.55, 0.30, 0.05), rough=0.4,
                          emission=(1.0, 0.55, 0.10), emission_strength=2.4)  # 琥珀电量窗（区别于电池组蓝光）
MAT_METAL = make_material("metal", (0.30, 0.30, 0.32), rough=0.5, metallic=0.8)

objs = []

def add_box(name, sx, sy, sz, x, y, z, mat=MAT_DARK, bevel=0.0):
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

# 三联立式弹匣（单匣 0.055×0.045×0.16，顶部金属托弹板，正面琥珀电量窗）+ 底座托盘
for i in range(3):
    x = (i - 1) * 0.065
    add_box("mag_%d" % i, 0.055, 0.045, 0.16, x, 0, 0.09, MAT_DARK, bevel=0.008)
    add_box("feed_%d" % i, 0.045, 0.035, 0.015, x, 0, 0.175, MAT_METAL, bevel=0.003)
    add_box("window_%d" % i, 0.030, 0.006, 0.10, x, -0.026, 0.09, MAT_AMBER, bevel=0.002)
add_box("tray", 0.22, 0.07, 0.02, 0, 0, 0.01, MAT_METAL, bevel=0.006)

bpy.ops.object.select_all(action='DESELECT')
for o in objs:
    o.select_set(True)
bpy.context.view_layer.objects.active = objs[0]
bpy.ops.object.join()
bpy.context.active_object.name = "pickup_pistol_ammo"
path = os.path.join(OUT_DIR, "pickup_pistol_ammo.glb")
bpy.ops.export_scene.gltf(filepath=path, export_format='GLB',
                          use_selection=True, export_yup=True,
                          export_apply=True, export_animations=False)
print("KIMI_BLENDER_RESULT={\"kit\": \"pickup_pistol_ammo\", \"verts\": %d, \"path\": \"%s\"}" % (
    len(bpy.context.active_object.data.vertices), path.replace("\\", "/")))
