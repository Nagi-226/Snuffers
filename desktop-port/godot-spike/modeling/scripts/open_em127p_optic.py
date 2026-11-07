"""Open the EM-127P upper optic and restore original rear cyan UVs, without added panels."""
import bpy
import bmesh
import numpy as np
import os
import sys

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if len(argv) != 2:
    raise SystemExit("usage: open_em127p_optic.py <input.glb> <output.glb>")
SRC, DST = map(os.path.abspath, argv)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
if len(meshes) != 1:
    raise RuntimeError("expected one EM-127P mesh, got %d" % len(meshes))
obj = meshes[0]


def base_color_image(material):
    if not material or not material.use_nodes:
        return None
    for node in material.node_tree.nodes:
        if node.type == "TEX_IMAGE" and node.image:
            return node.image
    return None


images = {}
for material in obj.data.materials:
    image = base_color_image(material)
    if image:
        pixels = np.empty(image.size[0] * image.size[1] * 4, dtype=np.float32)
        image.pixels.foreach_get(pixels)
        images[image.name] = (image, pixels.reshape((-1, 4)))


def is_cyan(image_name, uv):
    image, pixels = images[image_name]
    width, height = image.size
    x = min(width - 1, max(0, int((uv.x % 1.0) * width)))
    y = min(height - 1, max(0, int((uv.y % 1.0) * height)))
    r, g, b, _ = pixels[y * width + x]
    return b > 0.3 and g > 0.2 and r < 0.2 and b > r * 1.8


uv_layer = obj.data.uv_layers.active.data
cyan_uv_faces = []
for poly in obj.data.polygons:
    center = poly.center
    if not (0.10 < center.z < 0.20 and -0.48 < center.y < -0.38 and abs(center.x) < 0.06):
        continue
    image = base_color_image(obj.data.materials[poly.material_index])
    if image and all(is_cyan(image.name, uv_layer[i].uv) for i in poly.loop_indices):
        cyan_uv_faces.append(poly)
if len(cyan_uv_faces) < 4:
    raise RuntimeError("original cyan UV region not found: %d" % len(cyan_uv_faces))

cyan_material = obj.data.materials[0].copy()
cyan_material.name = "EM127P_Original_Cyan_Restore"
cyan_bsdf = cyan_material.node_tree.nodes.get("Principled BSDF")
cyan_bsdf.inputs["Emission Color"].default_value = (0.0, 0.45, 0.8, 1.0)
cyan_bsdf.inputs["Emission Strength"].default_value = 0.8
cyan_index = len(obj.data.materials)
obj.data.materials.append(cyan_material)
cyan_uv = sum((uv_layer[i].uv for poly in cyan_uv_faces for i in poly.loop_indices), start=__import__("mathutils").Vector((0, 0))) / sum(len(poly.loop_indices) for poly in cyan_uv_faces)
panel_faces = []
for poly in obj.data.polygons:
    center = poly.center
    in_original_panel = 0.10 < center.z < 0.20 and -0.455 < center.y < -0.425 and abs(center.x) < 0.035
    if in_original_panel:
        panel_faces.append(poly)
for poly in panel_faces:
    poly.material_index = cyan_index
    for loop_index in poly.loop_indices:
        uv_layer[loop_index].uv = cyan_uv
print("ORIGINAL_PANEL_FACES_RESTORED", len(panel_faces), "REAR_GEOMETRY_ADDED 0", flush=True)

CENTER_Z = 0.27
HALF_X = 0.015
HALF_Z = 0.012
selected = []
for poly in obj.data.polygons:
    center = poly.center
    ellipse = (center.x / 0.018) ** 2 + ((center.z - CENTER_Z) / 0.015) ** 2
    if abs(center.y) < 0.6 and ellipse < 1.0:
        selected.append(poly.index)
if len(selected) < 4:
    raise RuntimeError("too few upper optic covers: %d" % len(selected))

lens_material = bpy.data.materials.new("EM127P_Holographic_Glass")
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

bm = bmesh.new()
bm.from_mesh(obj.data)
bm.faces.ensure_lookup_table()
bmesh.ops.delete(bm, geom=[bm.faces[index] for index in selected], context="FACES")
vertices = [
    bm.verts.new((-HALF_X, 0.0, CENTER_Z - HALF_Z)),
    bm.verts.new((HALF_X, 0.0, CENTER_Z - HALF_Z)),
    bm.verts.new((HALF_X, 0.0, CENTER_Z + HALF_Z)),
    bm.verts.new((-HALF_X, 0.0, CENTER_Z + HALF_Z)),
]
glass = bm.faces.new(vertices)
glass.material_index = lens_index
bm.to_mesh(obj.data)
bm.free()
obj.data.update()
print("UPPER_OPTIC_COVERS_REMOVED", len(selected), flush=True)
print("LENS_CENTER_VIEWMODEL", (0.03, 0.03 + 0.48 * CENTER_Z, 0.04), flush=True)

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
