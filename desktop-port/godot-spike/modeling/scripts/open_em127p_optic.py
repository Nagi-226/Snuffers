"""Open the upper EM-127P optic and restore its rear cyan energy panel."""
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
cyan_faces = []
for poly in obj.data.polygons:
    center = poly.center
    if not (0.10 < center.z < 0.20 and -0.48 < center.y < -0.38 and abs(center.x) < 0.06):
        continue
    image = base_color_image(obj.data.materials[poly.material_index])
    if image and all(is_cyan(image.name, uv_layer[i].uv) for i in poly.loop_indices):
        cyan_faces.append(poly)
if len(cyan_faces) < 4:
    raise RuntimeError("rear cyan panel not found: %d" % len(cyan_faces))
rear_faces = []
for poly in obj.data.polygons:
    center = poly.center
    in_panel = 0.10 < center.z < 0.20 and -0.48 < center.y < -0.38 and abs(center.x) < 0.06
    if in_panel and abs(poly.normal.y) > 0.65:
        rear_faces.append(poly)

glow_material = bpy.data.materials.new("EM127P_Rear_Energy_Panel")
glow_material.use_nodes = True
glow_material.diffuse_color = (0.01, 0.3, 0.55, 1.0)
glow_bsdf = glow_material.node_tree.nodes.get("Principled BSDF")
glow_bsdf.inputs["Base Color"].default_value = (0.01, 0.3, 0.55, 1.0)
glow_bsdf.inputs["Emission Color"].default_value = (0.0, 0.45, 0.8, 1.0)
glow_bsdf.inputs["Emission Strength"].default_value = 0.8
glow_bsdf.inputs["Roughness"].default_value = 0.28
glow_index = len(obj.data.materials)
obj.data.materials.append(glow_material)
for poly in rear_faces:
    poly.material_index = glow_index
print("REAR_GLOW_FACES", len(rear_faces), flush=True)

CENTER_Z = 0.27
HALF_X = 0.015
HALF_Z = 0.012
selected = []
for poly in obj.data.polygons:
    center = poly.center
    ellipse = (center.x / 0.018) ** 2 + ((center.z - CENTER_Z) / 0.015) ** 2
    if abs(center.y) < 0.06 and ellipse < 1.0:
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
