## export_host_fbx.py — host_parasite.glb → FBX（Mixamo 自动绑骨上传准备，2026-10-23）
## 用法：blender -b --python export_host_fbx.py -- <in.glb> <out.fbx>
## Mixamo 上传要求 FBX/OBJ；原始 FBX 按资产卫生不入库（ATTRIBUTION 约束 #7）。
import bpy
import sys

argv = sys.argv[sys.argv.index("--") + 1:]
src, out = argv[0], argv[1]

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
for o in bpy.data.objects:
    if o.type == "MESH":
        d = o.dimensions
        print("HOST mesh=%s dims=%.2f x %.2f x %.2f (blender xyz)" % (o.name, d.x, d.y, d.z))
bpy.ops.export_scene.fbx(filepath=out, apply_unit_scale=True)
print("HOST exported -> %s" % out)
