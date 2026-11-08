"""Remove only the EM-40T-1 scope's rear protruding assembly."""
import bpy
import os
import sys

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if len(argv) != 2:
    raise SystemExit("usage: trim_em40t1_scope.py <input.glb> <output.glb>")
SRC, DST = map(os.path.abspath, argv)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
if len(meshes) != 1:
    raise RuntimeError("expected one EM-40T-1 mesh, got %d" % len(meshes))
obj = meshes[0]
selected = [poly for poly in obj.data.polygons if poly.center.z > 0.15 and poly.center.y < 0.08 and abs(poly.center.x) < 0.055]
if len(selected) < 20:
    raise RuntimeError("too few rear scope faces: %d" % len(selected))

import bmesh
bm = bmesh.new()
bm.from_mesh(obj.data)
faces = [face for face in bm.faces if any(v.co.z > 0.15 and v.co.y < 0.08 and abs(v.co.x) < 0.055 for v in face.verts)]
bmesh.ops.delete(bm, geom=faces, context="FACES")
bm.to_mesh(obj.data)
bm.free()
obj.data.update()
obj.data.calc_loop_triangles()
if len(obj.data.loop_triangles) < 60000:
    raise RuntimeError("unexpected excessive removal: %d" % len(obj.data.loop_triangles))
print("SCOPE_PROTRUSION_FACES_REMOVED", len(selected), flush=True)
print("TRIANGLES_REMAINING", len(obj.data.loop_triangles), flush=True)

bpy.ops.object.select_all(action="DESELECT")
obj.select_set(True)
bpy.context.view_layer.objects.active = obj
bpy.ops.export_scene.gltf(
    filepath=DST,
    export_format="GLB",
    use_selection=True,
    export_yup=True,
    export_apply=True,
    export_cameras=False,
    export_lights=False,
    export_animations=False,
    export_skins=False,
    export_morph=False,
    export_draco_mesh_compression_enable=False,
)
print("EXPORTED", DST, os.path.getsize(DST), flush=True)
