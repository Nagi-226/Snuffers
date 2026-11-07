"""Open the EM-86B sight channel in the final oriented game model."""
import bpy
import bmesh
import math
import mathutils
import os
import sys

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if len(argv) != 3:
    raise SystemExit("usage: open_em86b_optic.py <input.glb> <output.glb> <preview_dir>")
SRC, DST, PREVIEW = map(os.path.abspath, argv)
os.makedirs(PREVIEW, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
if not meshes:
    raise RuntimeError("no mesh objects")

CENTER_Y = 0.03
CENTER_Z = 0.20
HALF_LENGTH = 0.18
BORE_RADIUS = 0.032
removed = 0
for obj in meshes:
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    blocked = []
    for face in bm.faces:
        center = face.calc_center_median()
        radial = math.hypot(center.x, center.z - CENTER_Z)
        if abs(center.y - CENTER_Y) <= HALF_LENGTH and radial < BORE_RADIUS:
            blocked.append(face)
    removed += len(blocked)
    bmesh.ops.delete(bm, geom=blocked, context="FACES")
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
print("BORE_FACES_REMOVED", removed, flush=True)
if removed < 20:
    raise RuntimeError("too few obstructing faces found; check optic calibration")

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

scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 900
scene.render.resolution_y = 900
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.world = bpy.data.worlds.new("PreviewWorld")
scene.world.use_nodes = True
scene.world.node_tree.nodes["Background"].inputs[0].default_value = (0.55, 0.58, 0.62, 1.0)
scene.world.node_tree.nodes["Background"].inputs[1].default_value = 0.8
cam_data = bpy.data.cameras.new("PreviewCamera")
cam_data.type = "ORTHO"
cam_data.ortho_scale = 0.42
cam = bpy.data.objects.new("PreviewCamera", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam
target = mathutils.Vector((0, CENTER_Y, CENTER_Z))
for label, direction in [("ocular", (0, 1, 0)), ("objective", (0, -1, 0)), ("side", (1, 0, 0))]:
    cam.location = target + mathutils.Vector(direction) * 1.5
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = os.path.join(PREVIEW, label + ".png")
    bpy.ops.render.render(write_still=True)
print("EXPORTED", DST, os.path.getsize(DST), flush=True)
