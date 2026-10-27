"""Inspect generated GLB dimensions and render axis-identified views without modifying sources."""
import bpy
import math
import mathutils
import os
import sys

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if len(argv) != 2:
    raise SystemExit("usage: <input.glb> <output-directory>")
SRC = os.path.abspath(argv[0])
OUT = os.path.abspath(argv[1])
os.makedirs(OUT, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
if not meshes:
    raise RuntimeError("no mesh objects")
lo = mathutils.Vector((1e18, 1e18, 1e18))
hi = -lo
triangles = 0
for obj in meshes:
    obj.data.calc_loop_triangles()
    triangles += len(obj.data.loop_triangles)
    for corner in obj.bound_box:
        point = obj.matrix_world @ mathutils.Vector(corner)
        lo = mathutils.Vector(map(min, lo, point))
        hi = mathutils.Vector(map(max, hi, point))
center = (lo + hi) * 0.5
dims = hi - lo
print("ASSET", os.path.basename(SRC), "BOUNDS", tuple(lo), tuple(hi), "DIMS", tuple(dims), "TRIANGLES", triangles, flush=True)

scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 800
scene.render.resolution_y = 600
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.world = bpy.data.worlds.new("InspectionWorld")
scene.world.use_nodes = True
scene.world.node_tree.nodes["Background"].inputs[0].default_value = (0.65, 0.65, 0.65, 1.0)
scene.world.node_tree.nodes["Background"].inputs[1].default_value = 0.7
for name, loc in [("Key", center + mathutils.Vector((1, -1, 1)) * max(dims) * 3),
                  ("Fill", center + mathutils.Vector((-1, 1, 0.7)) * max(dims) * 3)]:
    data = bpy.data.lights.new(name, "AREA")
    data.energy = max(dims) ** 2 * 350
    data.shape = "DISK"
    data.size = max(dims) * 2
    obj = bpy.data.objects.new(name, data)
    scene.collection.objects.link(obj)
    obj.location = loc
    obj.rotation_euler = (center - obj.location).to_track_quat("-Z", "Y").to_euler()
cam_data = bpy.data.cameras.new("InspectionCamera")
cam_data.type = "ORTHO"
cam_data.ortho_scale = max(dims) * 1.25
cam = bpy.data.objects.new("InspectionCamera", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam
views = {
    "plus_x": center + mathutils.Vector((1, 0, 0)) * max(dims) * 4,
    "minus_x": center + mathutils.Vector((-1, 0, 0)) * max(dims) * 4,
    "plus_y": center + mathutils.Vector((0, 1, 0)) * max(dims) * 4,
    "minus_y": center + mathutils.Vector((0, -1, 0)) * max(dims) * 4,
    "top": center + mathutils.Vector((0, 0, 1)) * max(dims) * 4,
}
for label, location in views.items():
    cam.location = location
    cam.rotation_euler = (center - location).to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = os.path.join(OUT, label + ".png")
    bpy.ops.render.render(write_still=True)
print("INSPECTED", OUT, flush=True)
