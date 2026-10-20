import bpy, sys
from mathutils import Vector

argv = sys.argv[sys.argv.index("--")+1:]
src, dst = argv[0], argv[1]

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
meshes = [ob for ob in bpy.data.objects if ob.type == 'MESH']
bpy.ops.object.select_all(action='DESELECT')
for m in meshes:
    m.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
bpy.ops.object.join()
ob = bpy.context.view_layer.objects.active
mod = ob.modifiers.new("dec", 'DECIMATE')
mod.ratio = 30000.0 / max(30000, len(ob.data.polygons))
bpy.ops.object.modifier_apply(modifier="dec")
# strip materials to 1 for speed
ob.data.materials.clear()
mat = bpy.data.materials.new("proxy")
ob.data.materials.append(mat)
bpy.ops.export_scene.gltf(filepath=dst, export_yup=True, export_apply=True)
print("PROXY_OK", len(ob.data.polygons))
