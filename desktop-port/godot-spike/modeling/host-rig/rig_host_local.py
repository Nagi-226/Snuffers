import bpy
import bmesh
import math
import os
import sys
from mathutils import Matrix, Vector

argv = sys.argv[sys.argv.index("--") + 1:]
src, skeleton_fbx, out, preview_prefix = argv[:4]
ARM_ANGLE = math.radians(85.0)
RIG_HEIGHT = 205.0734

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
mesh = next(o for o in bpy.context.scene.objects if o.type == "MESH")
bpy.context.view_layer.objects.active = mesh
mesh.select_set(True)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

bm = bmesh.new()
bm.from_mesh(mesh.data)
bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=0.001)
bm.to_mesh(mesh.data)
bm.free()


def smoothstep(value):
    t = max(0.0, min(1.0, value))
    return t * t * (3.0 - 2.0 * t)


def rotate_about(point, pivot, axis, angle):
    return pivot + Matrix.Rotation(angle, 3, axis) @ (point - pivot)


for vertex in mesh.data.vertices:
    source = vertex.co.copy()
    point = source.copy()
    side = 1.0 if source.y >= 0.0 else -1.0
    leg_weight = 1.0 - smoothstep((source.z + 0.12) / 0.08)
    leg_weight *= 1.0 - smoothstep((abs(source.y) - 0.16) / 0.05)
    if leg_weight > 0.0:
        pivot = Vector((0.0, side * 0.07, -0.05))
        rotated = rotate_about(source, pivot, "Y", side * math.radians(10.0))
        rotated = rotate_about(rotated, pivot, "X", side * math.radians(5.0))
        point += leg_weight * (rotated - source)
    head_weight = smoothstep((source.z - 0.30) / 0.06)
    head_weight *= 1.0 - smoothstep((abs(source.y) - 0.10) / 0.06)
    head_weight *= smoothstep((source.x + 0.05) / 0.06)
    if head_weight > 0.0:
        rotated = rotate_about(source, Vector((0.0, 0.0, 0.31)), "Y", math.radians(-20.0))
        point += head_weight * (rotated - source)
    vertex.co = point
mesh.data.update()

before_import = set(bpy.context.scene.objects)
bpy.ops.import_scene.fbx(filepath=skeleton_fbx)
imported = set(bpy.context.scene.objects) - before_import
rig = next(o for o in imported if o.type == "ARMATURE")
for obj in imported:
    if obj != rig:
        bpy.data.objects.remove(obj, do_unlink=True)
rig.animation_data_clear()
scale = 1.0 / RIG_HEIGHT
rig.matrix_world = Matrix.Translation((0.0, 0.0, -0.5)) @ Matrix.Rotation(math.pi / 2.0, 4, "Z") @ Matrix.Rotation(math.pi / 2.0, 4, "X") @ Matrix.Diagonal((scale, scale, scale, 1.0))
bpy.ops.object.select_all(action="DESELECT")
rig.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
for pose_bone in rig.pose.bones:
    pose_bone.matrix_basis = Matrix.Identity(4)
bpy.context.view_layer.update()

bpy.ops.object.mode_set(mode="EDIT")
for side_name, sign in (("Left", 1.0), ("Right", -1.0)):
    for bone in rig.data.edit_bones:
        if bone.name.startswith("mixamorig:" + side_name) and ("Arm" in bone.name or "Hand" in bone.name or "Shoulder" in bone.name):
            bone.head.y += sign * 0.026
            bone.tail.y += sign * 0.026
            bone.head.z += 0.0376
            bone.tail.z += 0.0376
bpy.ops.object.mode_set(mode="OBJECT")

bpy.ops.object.select_all(action="DESELECT")
mesh.select_set(True)
rig.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.parent_set(type="ARMATURE_AUTO")
print("HOST_RIG automatic weights complete", flush=True)


def report(stage):
    depsgraph = bpy.context.evaluated_depsgraph_get()
    evaluated = mesh.evaluated_get(depsgraph)
    points = [evaluated.matrix_world @ v.co for v in evaluated.data.vertices]
    lo = tuple(round(min(p[i] for p in points), 4) for i in range(3))
    hi = tuple(round(max(p[i] for p in points), 4) for i in range(3))
    bones_lo = tuple(round(min(b.head_local[i] for b in rig.data.bones), 4) for i in range(3))
    bones_hi = tuple(round(max(b.head_local[i] for b in rig.data.bones), 4) for i in range(3))
    print("HOST_RIG_DEBUG", stage, "mesh", lo, hi, "bones", bones_lo, bones_hi,
          "parent", mesh.parent.name if mesh.parent else None,
          "world", [list(row) for row in mesh.matrix_world],
          "parent_inv", [list(row) for row in mesh.matrix_parent_inverse], flush=True)


report("bound")
for side_name, sign in (("Left", 1.0), ("Right", -1.0)):
    pose_bone = rig.pose.bones["mixamorig:" + side_name + "Arm"]
    pivot = pose_bone.bone.head_local.copy()
    transform = Matrix.Translation(pivot) @ Matrix.Rotation(sign * ARM_ANGLE, 4, "X") @ Matrix.Translation(-pivot)
    pose_bone.matrix = transform @ pose_bone.bone.matrix_local
bpy.context.view_layer.update()
report("posed")

bpy.ops.object.select_all(action="DESELECT")
mesh.select_set(True)
bpy.context.view_layer.objects.active = mesh
for modifier in list(mesh.modifiers):
    if modifier.type == "ARMATURE":
        bpy.ops.object.modifier_apply(modifier=modifier.name)
for pose_bone in rig.pose.bones:
    pose_bone.matrix_basis = Matrix.Identity(4)
armature_modifier = mesh.modifiers.new("Armature", "ARMATURE")
armature_modifier.object = rig
bpy.context.view_layer.update()
report("reset")
if len(argv) > 4:
    bpy.ops.wm.save_as_mainfile(filepath=argv[4])

mesh.select_set(True)
rig.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_yup=True,
                          export_apply=False, export_animations=False, export_skins=True,
                          export_rest_position_armature=True)
print("HOST_RIG exported " + out, flush=True)

scene = bpy.context.scene
scene.render.engine = "BLENDER_WORKBENCH"
scene.display.shading.light = "STUDIO"
scene.display.shading.color_type = "TEXTURE"
scene.display.shading.show_cavity = True
scene.render.resolution_x = 800
scene.render.resolution_y = 800
scene.render.resolution_percentage = 100
cam_data = bpy.data.cameras.new("VerifyCamera")
cam_data.type = "ORTHO"
cam_data.ortho_scale = 1.25
cam = bpy.data.objects.new("VerifyCamera", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam
center = Vector((0.0, 0.0, 0.0))
for tag, direction in (("front", Vector((1, 0, 0))),
                       ("side", Vector((0, 1, 0))),
                       ("three_quarter", Vector((1, -1, 0.35)))):
    cam.location = center + direction.normalized() * 2.5
    cam.rotation_euler = (center - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = preview_prefix + "_" + tag + ".png"
    bpy.ops.render.render(write_still=True)
