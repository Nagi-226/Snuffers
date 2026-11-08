"""Transplant the EM-57S-2 magazine tail cap onto the EM-40T-1 scope."""
import bpy
import mathutils
import os
import sys

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if len(argv) != 4:
    raise SystemExit("usage: transplant_em40t1_rear_cap.py <cap.glb> <material_source.glb> <launcher.glb> <output.glb>")
SRC, MAT_SRC, DST, OUT = map(os.path.abspath, argv)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=MAT_SRC)
material_source = next(obj for obj in bpy.context.scene.objects if obj.type == "MESH")
source_material = material_source.data.materials[0]
bpy.data.objects.remove(material_source, do_unlink=True)

bpy.ops.import_scene.gltf(filepath=SRC)
cap = next(obj for obj in bpy.context.scene.objects if obj.type == "MESH")
cap_mesh = cap.data
cap_mesh.materials.clear()
cap_mesh.materials.append(source_material)
blue_material = bpy.data.materials.new("EM57S2_MagazineTail_Blue")
blue_material.use_nodes = True
blue_bsdf = blue_material.node_tree.nodes.get("Principled BSDF")
blue_bsdf.inputs["Base Color"].default_value = (0.025, 0.38, 0.72, 1.0)
blue_bsdf.inputs["Metallic"].default_value = 0.25
blue_bsdf.inputs["Roughness"].default_value = 0.22
blue_bsdf.inputs["Emission Color"].default_value = (0.02, 0.28, 0.65, 1.0)
blue_bsdf.inputs["Emission Strength"].default_value = 0.45
cap_mesh.materials.append(blue_material)
points = [cap.matrix_world @ vertex.co for vertex in cap_mesh.vertices]
lo = mathutils.Vector(tuple(min(point[i] for point in points) for i in range(3)))
hi = mathutils.Vector(tuple(max(point[i] for point in points) for i in range(3)))
center = (lo + hi) * 0.5
for polygon in cap_mesh.polygons:
    radial = (polygon.center.x - center.x) ** 2 + (polygon.center.z - center.z) ** 2
    polygon.material_index = 1 if radial < 0.0004 and polygon.normal.y < -0.2 else 0
scale = 0.115 / max(hi.x - lo.x, hi.z - lo.z)
for vertex in cap_mesh.vertices:
    point = cap.matrix_world @ vertex.co
    vertex.co = ((point.x - center.x) * scale, (point.y - hi.y) * scale + 0.08, (point.z - center.z) * scale + 0.19)
cap.matrix_world = mathutils.Matrix.Identity(4)
cap_mesh.update()
bpy.ops.mesh.primitive_cylinder_add(vertices=48, radius=0.022, depth=0.0002, end_fill_type="NGON", location=(0, 0.0801, 0.19), rotation=(1.5707963268, 0, 0))
center_disk = bpy.context.object
center_disk.data.materials.append(blue_material)

bpy.ops.import_scene.gltf(filepath=DST)
target = next(obj for obj in bpy.context.scene.objects if obj.type == "MESH" and obj != cap and obj != center_disk)
bpy.ops.object.select_all(action="DESELECT")
target.select_set(True)
cap.select_set(True)
center_disk.select_set(True)
bpy.context.view_layer.objects.active = target
bpy.ops.object.join()
target.data.calc_loop_triangles()
if len(target.data.loop_triangles) < 60000:
    raise RuntimeError("unexpected triangle count: %d" % len(target.data.loop_triangles))
print("MAGAZINE_TAIL_FACES_TRANSPLANTED", len(cap_mesh.polygons), flush=True)
print("TRIANGLES_WITH_REAR_CAP", len(target.data.loop_triangles), flush=True)

bpy.ops.object.select_all(action="DESELECT")
target.select_set(True)
bpy.context.view_layer.objects.active = target
bpy.ops.export_scene.gltf(
    filepath=OUT,
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
print("EXPORTED", OUT, os.path.getsize(OUT), flush=True)
