"""Normalize a generated long-gun GLB without changing mesh geometry or textures.

blender -b --factory-startup --python-exit-code 1 --python normalize_long_gun.py -- \
    <input.glb> <output.glb> <target_length_m> [flip]
"""

import bpy
import math
import mathutils
import os
import sys

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if len(argv) < 3:
    raise SystemExit("usage: <input.glb> <output.glb> <target_length_m> [flip]")
SRC = os.path.abspath(argv[0])
DST = os.path.abspath(argv[1])
TARGET_LENGTH = float(argv[2])
FLIP = len(argv) > 3 and argv[3].lower() == "flip"

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
if len(meshes) != 1:
    raise RuntimeError("expected one generated mesh, got %d" % len(meshes))
if any(o.type != "MESH" for o in bpy.context.scene.objects):
    raise RuntimeError("generated input must contain mesh objects only")


def world_bbox():
    lo = mathutils.Vector((1e18, 1e18, 1e18))
    hi = mathutils.Vector((-1e18, -1e18, -1e18))
    for obj in meshes:
        for corner in obj.bound_box:
            point = obj.matrix_world @ mathutils.Vector(corner)
            lo = mathutils.Vector(map(min, lo, point))
            hi = mathutils.Vector(map(max, hi, point))
    return lo, hi


lo, hi = world_bbox()
dims = hi - lo
print("IMPORT_DIMS", tuple(dims), flush=True)
root = bpy.data.objects.new("WeaponRoot", None)
bpy.context.collection.objects.link(root)
for obj in list(bpy.context.scene.objects):
    if obj != root and obj.parent is None:
        obj.parent = root

if dims.x >= dims.y and dims.x >= dims.z:
    root.rotation_euler.rotate_axis("Z", math.radians(90.0))
elif dims.z >= dims.x and dims.z >= dims.y:
    root.rotation_euler.rotate_axis("X", math.radians(-90.0))
if FLIP:
    root.rotation_euler.rotate_axis("X", math.radians(180.0))
bpy.context.view_layer.update()
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)

lo, hi = world_bbox()
dims = hi - lo
center = (lo + hi) * 0.5
scale = TARGET_LENGTH / max(dims.x, dims.y, dims.z)
root.location = -center * scale
root.scale = (scale, scale, scale)
bpy.context.view_layer.update()
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
bpy.context.view_layer.update()
lo, hi = world_bbox()
print("FINAL_BOUNDS", tuple(lo), tuple(hi), "DIMS", tuple(hi - lo), flush=True)

os.makedirs(os.path.dirname(DST), exist_ok=True)
bpy.ops.export_scene.gltf(
    filepath=DST,
    export_format="GLB",
    export_yup=True,
    export_apply=False,
    export_cameras=False,
    export_lights=False,
    export_animations=False,
    export_skins=False,
    export_morph=False,
    export_draco_mesh_compression_enable=False,
)
print("EXPORTED", DST, os.path.getsize(DST), flush=True)
