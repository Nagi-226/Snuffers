"""Prepare a generated weapon/vehicle GLB for Godot while preserving its raw source.

blender -b --factory-startup --python-exit-code 1 --python prepare_generated_asset.py -- \
    <input.glb> <output.glb> <weapon|vehicle> <target_length_m> <triangle_target> <preview_dir>
"""
import bpy
import math
import mathutils
import os
import sys

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if len(argv) != 6:
    raise SystemExit("usage: <input.glb> <output.glb> <weapon|vehicle> <length_m> <triangles> <preview_dir>")
SRC, DST, KIND, TARGET_LENGTH, TARGET_TRIS, PREVIEW = (
    os.path.abspath(argv[0]), os.path.abspath(argv[1]), argv[2], float(argv[3]), int(argv[4]), os.path.abspath(argv[5]))
if KIND not in {"weapon", "vehicle"}:
    raise ValueError("kind must be weapon or vehicle")
os.makedirs(os.path.dirname(DST), exist_ok=True)
os.makedirs(PREVIEW, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
if not meshes:
    raise RuntimeError("no mesh objects")


def bounds():
    lo = mathutils.Vector((1e18, 1e18, 1e18))
    hi = mathutils.Vector((-1e18, -1e18, -1e18))
    for obj in meshes:
        for corner in obj.bound_box:
            point = obj.matrix_world @ mathutils.Vector(corner)
            lo = mathutils.Vector(map(min, lo, point))
            hi = mathutils.Vector(map(max, hi, point))
    return lo, hi


# Generated guns point along +Y; the JB-02 points along +X in Blender.
# Both finish pointing +Y, which glTF export maps to Godot -Z.
if KIND == "vehicle":
    turn = mathutils.Matrix.Rotation(math.radians(90.0), 4, "Z")
    for obj in meshes:
        if obj.parent is None:
            obj.matrix_world = turn @ obj.matrix_world
bpy.context.view_layer.update()
lo, hi = bounds()
dims = hi - lo
center = (lo + hi) * 0.5
scale = TARGET_LENGTH / max(dims)
for obj in meshes:
    if obj.parent is None:
        obj.location = (obj.location - center) * scale
        obj.scale *= scale
bpy.context.view_layer.update()
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
lo, hi = bounds()
center = (lo + hi) * 0.5
for obj in meshes:
    obj.location.x -= center.x
    obj.location.y -= center.y
    obj.location.z -= lo.z if KIND == "vehicle" else center.z
bpy.context.view_layer.update()

for image in bpy.data.images:
    if image.size[0] > 2048 or image.size[1] > 2048:
        ratio = min(2048 / image.size[0], 2048 / image.size[1])
        image.scale(max(1, int(image.size[0] * ratio)), max(1, int(image.size[1] * ratio)))

before = 0
for obj in meshes:
    obj.data.calc_loop_triangles()
    count = len(obj.data.loop_triangles)
    before += count
    if count > TARGET_TRIS:
        modifier = obj.modifiers.new("GameDecimate", "DECIMATE")
        modifier.ratio = TARGET_TRIS / count
        modifier.use_collapse_triangulate = True
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    obj.data.calc_loop_triangles()
    print("MESH", obj.name, "TRIANGLES", count, "->", len(obj.data.loop_triangles), flush=True)

lo, hi = bounds()
print("FINAL_BOUNDS", tuple(lo), tuple(hi), "DIMS", tuple(hi - lo), "SOURCE_TRIANGLES", before, flush=True)

scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 1000
scene.render.resolution_y = 750
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.world = bpy.data.worlds.new("PreviewWorld")
scene.world.use_nodes = True
scene.world.node_tree.nodes["Background"].inputs[0].default_value = (0.55, 0.58, 0.62, 1.0)
scene.world.node_tree.nodes["Background"].inputs[1].default_value = 0.8
center = (lo + hi) * 0.5
size = max(hi - lo)
for name, direction in [("Key", (1, -1, 1)), ("Fill", (-1, 1, 0.7))]:
    data = bpy.data.lights.new(name, "AREA")
    data.energy = size ** 2 * 400
    data.shape = "DISK"
    data.size = size * 2
    obj = bpy.data.objects.new(name, data)
    scene.collection.objects.link(obj)
    obj.location = center + mathutils.Vector(direction) * size * 3
    obj.rotation_euler = (center - obj.location).to_track_quat("-Z", "Y").to_euler()
cam_data = bpy.data.cameras.new("PreviewCamera")
cam_data.type = "ORTHO"
cam_data.ortho_scale = size * 1.25
cam = bpy.data.objects.new("PreviewCamera", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam
views = {
    "side": (1, 0, 0),
    "front": (0, 1, 0),
    "rear": (0, -1, 0),
    "iso": (1.4, 1.8, 1.0),
}
for label, direction in views.items():
    cam.location = center + mathutils.Vector(direction).normalized() * size * 4
    cam.rotation_euler = (center - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = os.path.join(PREVIEW, label + ".png")
    bpy.ops.render.render(write_still=True)

bpy.ops.object.select_all(action="DESELECT")
for obj in meshes:
    obj.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
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
