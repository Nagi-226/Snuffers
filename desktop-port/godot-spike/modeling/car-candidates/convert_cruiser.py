## convert_cruiser.py — Fairheaven Cop Cruiser（Sketchfab CC-BY）gltf → GLB 烘焙（2026-10-23）
## 用法：blender -b --python convert_cruiser.py -- <pack_dir> <out_glb>
## 整车单场景，直接全量导入导出；打印尺寸供碰撞盒定参。
import bpy
import os
import sys

argv = sys.argv[sys.argv.index("--") + 1:]
pack_dir, out_glb = argv[0], argv[1]

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=os.path.join(pack_dir, "scene.gltf"))
bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.gltf(filepath=out_glb, export_format="GLB", use_selection=True)
for o in bpy.data.objects:
    if o.type == "MESH":
        d = o.dimensions
        print("CRUISER mesh=%s dims=%.2f x %.2f x %.2f" % (o.name, d.x, d.y, d.z))
print("CRUISER exported -> %s" % out_glb)
