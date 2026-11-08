"""Make only EM-57S-2 sight-covering faces transparent, preserving all geometry."""
import bpy
import os
import sys

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if len(argv) != 2:
    raise SystemExit("usage: open_em57s2_optic.py <input.glb> <output.glb>")
SRC, DST = map(os.path.abspath, argv)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
if len(meshes) != 1:
    raise RuntimeError("expected one EM-57S-2 mesh, got %d" % len(meshes))
obj = meshes[0]

CENTER_Z = 0.16
selected = []
for poly in obj.data.polygons:
    center = poly.center
    ellipse = (center.x / 0.026) ** 2 + ((center.z - CENTER_Z) / 0.026) ** 2
    if abs(center.y) < 0.36 and ellipse < 1.0:
        selected.append(poly)
if len(selected) < 4:
    raise RuntimeError("too few optic covers: %d" % len(selected))

lens_material = bpy.data.materials.new("EM57S2_Holographic_Glass")
lens_material.use_nodes = True
lens_material.diffuse_color = (0.035, 0.32, 0.48, 0.06)
lens_material.surface_render_method = "DITHERED"
lens_bsdf = lens_material.node_tree.nodes.get("Principled BSDF")
lens_bsdf.inputs["Base Color"].default_value = (0.035, 0.32, 0.48, 0.06)
lens_bsdf.inputs["Alpha"].default_value = 0.06
lens_bsdf.inputs["Metallic"].default_value = 0.0
lens_bsdf.inputs["Roughness"].default_value = 0.12
lens_index = len(obj.data.materials)
obj.data.materials.append(lens_material)
for poly in selected:
    poly.material_index = lens_index
print("OPTIC_FACES_MADE_TRANSPARENT", len(selected), flush=True)
print("OPTIC_FACES_DELETED 0", flush=True)

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
