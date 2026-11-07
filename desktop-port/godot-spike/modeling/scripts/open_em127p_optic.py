"""Open the upper EM-127P optic and add clean rear emissive inlays."""
import bpy
import bmesh
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

bm = bmesh.new()
bm.from_mesh(obj.data)
bm.faces.ensure_lookup_table()
bmesh.ops.delete(bm, geom=[bm.faces[index] for index in selected], context="FACES")


def add_rear_quad(x0, x1, z0, z1, y, material_index):
    vertices = [
        bm.verts.new((x0, y, z0)),
        bm.verts.new((x1, y, z0)),
        bm.verts.new((x1, y, z1)),
        bm.verts.new((x0, y, z1)),
    ]
    face = bm.faces.new(vertices)
    face.material_index = material_index


add_rear_quad(-HALF_X, HALF_X, CENTER_Z - HALF_Z, CENTER_Z + HALF_Z, 0.0, lens_index)
add_rear_quad(-0.027, 0.027, 0.12, 0.175, -0.448, glow_index)
add_rear_quad(-0.043, -0.038, -0.16, 0.105, -0.472, glow_index)
bm.to_mesh(obj.data)
bm.free()
obj.data.update()
print("UPPER_OPTIC_COVERS_REMOVED", len(selected), flush=True)
print("REAR_GLOW_VERTICES 8", flush=True)
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
