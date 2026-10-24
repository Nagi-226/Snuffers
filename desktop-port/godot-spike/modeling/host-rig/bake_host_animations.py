import bpy
import math
import os
import sys
from mathutils import Matrix, Vector

argv = sys.argv[sys.argv.index("--") + 1:]
rigged_glb, mixamo_dir, out, preview_dir = argv[:4]
CLIPS = tuple(argv[4].split(",")) if len(argv) > 4 else ("idle", "walk", "run", "attack", "death")
SCALE = 100.0 / 205.0734
SOURCE_TO_TARGET = Matrix.Rotation(math.pi / 2.0, 4, "Z")

if rigged_glb.lower().endswith(".blend"):
    bpy.ops.wm.open_mainfile(filepath=rigged_glb)
else:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=rigged_glb)
rig = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
mesh = next(o for o in bpy.context.scene.objects if o.type == "MESH")
rig.animation_data_create()
scene = bpy.context.scene
scene.render.fps = 30


def ordered_bones(armature):
    result = []
    def visit(bone):
        result.append(bone.name)
        for child in bone.children:
            visit(child)
    for root in armature.bones:
        if root.parent is None:
            visit(root)
    return result


bone_names = ordered_bones(rig.data)
for clip_name in CLIPS:
    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.fbx(filepath=os.path.join(mixamo_dir, clip_name + ".fbx"))
    imported = set(bpy.context.scene.objects) - before
    source_rig = next(o for o in imported if o.type == "ARMATURE")
    source_action = source_rig.animation_data.action
    source_world = source_rig.matrix_world.copy()
    action = bpy.data.actions.new(clip_name)
    action.use_fake_user = True
    rig.animation_data.action = action
    for pose_bone in rig.pose.bones:
        pose_bone.matrix_basis = Matrix.Identity(4)
        pose_bone.rotation_mode = "QUATERNION"

    for frame in range(int(source_action.frame_range[0]), int(source_action.frame_range[1]) + 1):
        source_rig.animation_data.action = source_action
        scene.frame_set(frame)
        bpy.context.view_layer.update()
        for bone_name in bone_names:
            source_bone = source_rig.data.bones[bone_name]
            source_pose = source_rig.pose.bones[bone_name].matrix.copy()
            source_pose_world = source_world @ source_pose
            source_rest_world = source_world @ source_bone.matrix_local
            target_rest = rig.data.bones[bone_name].matrix_local.copy()
            translation_delta = SOURCE_TO_TARGET.to_3x3() @ (source_pose_world.translation - source_rest_world.translation)
            if bone_name == "mixamorig:Hips" and clip_name != "death":
                translation_delta.x = 0.0
                translation_delta.y = 0.0
            translation = target_rest.translation + translation_delta * SCALE
            rotation = SOURCE_TO_TARGET.to_quaternion() @ source_pose_world.to_quaternion()
            target_pose = Matrix.LocRotScale(translation, rotation, Vector((1.0, 1.0, 1.0)))
            pose_bone = rig.pose.bones[bone_name]
            pose_bone.matrix = target_pose
            bpy.context.view_layer.update()
            pose_bone.keyframe_insert("location", frame=frame, group=bone_name)
            pose_bone.keyframe_insert("rotation_quaternion", frame=frame, group=bone_name)

    track = rig.animation_data.nla_tracks.new()
    track.name = clip_name
    strip = track.strips.new(clip_name, int(action.frame_range[0]), action)
    strip.name = clip_name
    track.mute = True
    if clip_name == "death":
        for debug_frame in (1, 45, 90):
            scene.frame_set(debug_frame)
            bpy.context.view_layer.update()
            evaluated = mesh.evaluated_get(bpy.context.evaluated_depsgraph_get())
            points = [evaluated.matrix_world @ v.co for v in evaluated.data.vertices]
            lo = tuple(round(min(p[i] for p in points), 3) for i in range(3))
            hi = tuple(round(max(p[i] for p in points), 3) for i in range(3))
            print("HOST_BAKE_DEBUG", debug_frame, "hips", tuple(rig.pose.bones["mixamorig:Hips"].matrix.translation),
                  "mesh", lo, hi, flush=True)
    rig.animation_data.action = None
    for pose_bone in rig.pose.bones:
        pose_bone.matrix_basis = Matrix.Identity(4)
    print("HOST_BAKE", clip_name, "frames", tuple(action.frame_range), flush=True)
    for obj in imported:
        bpy.data.objects.remove(obj, do_unlink=True)
    bpy.data.actions.remove(source_action)

rig.animation_data.action = None
scene.frame_set(1)
bpy.ops.object.select_all(action="DESELECT")
mesh.select_set(True)
rig.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_yup=True,
                          export_apply=False, export_animations=True,
                          export_animation_mode="NLA_TRACKS", export_skins=True,
                          export_rest_position_armature=True, export_anim_slide_to_zero=True)
print("HOST_BAKE exported " + out, flush=True)

os.makedirs(preview_dir, exist_ok=True)
scene.render.engine = "BLENDER_WORKBENCH"
scene.display.shading.light = "STUDIO"
scene.display.shading.color_type = "TEXTURE"
scene.display.shading.show_cavity = True
scene.render.resolution_x = 640
scene.render.resolution_y = 640
scene.render.resolution_percentage = 100
cam_data = bpy.data.cameras.new("VerifyCamera")
cam_data.type = "ORTHO"
cam_data.ortho_scale = 1.35
cam = bpy.data.objects.new("VerifyCamera", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam
cam.location = Vector((2.5, 0.0, 0.0))
cam.rotation_euler = (Vector((0.0, 0.0, 0.0)) - cam.location).to_track_quat("-Z", "Y").to_euler()

for track in rig.animation_data.nla_tracks:
    action = track.strips[0].action
    rig.animation_data.action = action
    for tag, fraction in (("start", 0.1), ("mid", 0.5), ("end", 0.9)):
        frame = round(action.frame_range[0] + (action.frame_range[1] - action.frame_range[0]) * fraction)
        scene.frame_set(frame)
        scene.render.filepath = os.path.join(preview_dir, track.name + "_" + tag + ".png")
        bpy.ops.render.render(write_still=True)
    rig.animation_data.action = None
