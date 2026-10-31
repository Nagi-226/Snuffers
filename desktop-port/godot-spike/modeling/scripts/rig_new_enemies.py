import bpy
import json
import math
import os
import sys
from mathutils import Vector


def segment_distance(point, head, tail):
    line = tail - head
    t = max(0.0, min(1.0, (point - head).dot(line) / max(line.length_squared, 1e-10)))
    return (point - (head + line * t)).length


def create_rig(name, bone_specs):
    arm = bpy.data.armatures.new(name + "_skeleton")
    rig = bpy.data.objects.new(name + "_rig", arm)
    bpy.context.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    rig.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    for bone_name, head, tail in bone_specs:
        bone = arm.edit_bones.new(bone_name)
        bone.head = head
        bone.tail = tail
    bpy.ops.object.mode_set(mode="OBJECT")
    rig.select_set(False)
    return rig


def bind(mesh, rig, bone_specs):
    groups = {name: mesh.vertex_groups.new(name=name) for name, _, _ in bone_specs}
    for vertex in mesh.data.vertices:
        distances = []
        for name, head, tail in bone_specs:
            distances.append((segment_distance(vertex.co, head, tail), name))
        distances.sort()
        weights = []
        for distance, name in distances[:3]:
            weights.append((1.0 / max(distance, 0.015) ** 4, name))
        total = sum(weight for weight, _ in weights)
        for weight, name in weights:
            groups[name].add([vertex.index], weight / total, "REPLACE")
    modifier = mesh.modifiers.new("EnemyRig", "ARMATURE")
    modifier.object = rig
    mesh.parent = rig


def make_action(rig, name, length, poses):
    action = bpy.data.actions.new(name)
    rig.animation_data.action = action
    for frame in range(1, length + 1):
        for bone in rig.pose.bones:
            bone.location = (0, 0, 0)
            bone.rotation_euler = (0, 0, 0)
            bone.scale = (1, 1, 1)
        for bone_name, values in poses.get(frame, {}).items():
            bone = rig.pose.bones[bone_name]
            for prop, value in values.items():
                setattr(bone, prop, value)
        for bone in rig.pose.bones:
            bone.keyframe_insert("location", frame=frame)
            bone.keyframe_insert("rotation_euler", frame=frame)
            bone.keyframe_insert("scale", frame=frame)
    track = rig.animation_data.nla_tracks.new()
    track.name = name
    strip = track.strips.new(name, 1, action)
    strip.name = name
    rig.animation_data.action = None


def spore_bones():
    specs = [("core", Vector((0, 0, 0.04)), Vector((0, 0, 0.26))),
             ("shell", Vector((0, 0, 0.08)), Vector((0, 0, 0.3)))]
    points = [(-0.3, -0.4), (0.3, -0.4), (-0.32, 0.0), (0.32, 0.0), (-0.24, 0.4), (0.24, 0.4)]
    for index, (x, y) in enumerate(points):
        specs.append(("pseudopod_%d" % index, Vector((x * 0.55, y * 0.55, 0.06)), Vector((x, y, 0.03))))
    return specs


def hulking_bones():
    return [
        ("hips", Vector((0, 0, 0.24)), Vector((0, 0, 0.4))),
        ("spine", Vector((0, 0, 0.4)), Vector((0, 0, 0.58))),
        ("chest", Vector((0, 0, 0.58)), Vector((0, 0, 0.75))),
        ("head", Vector((0, 0, 0.75)), Vector((0, 0, 0.9))),
        ("upper_arm_r", Vector((-0.23, 0, 0.58)), Vector((-0.38, 0, 0.43))),
        ("forearm_r", Vector((-0.38, 0, 0.43)), Vector((-0.47, 0, 0.25))),
        ("hand_r", Vector((-0.47, 0, 0.25)), Vector((-0.48, 0, 0.1))),
        ("upper_arm_l", Vector((0.23, 0, 0.58)), Vector((0.32, 0, 0.43))),
        ("forearm_l", Vector((0.32, 0, 0.43)), Vector((0.28, 0, 0.27))),
        ("hand_l", Vector((0.28, 0, 0.27)), Vector((0.26, 0, 0.15))),
        ("thigh_r", Vector((-0.13, 0, 0.28)), Vector((-0.14, 0, 0.15))),
        ("shin_r", Vector((-0.14, 0, 0.15)), Vector((-0.14, 0, 0.04))),
        ("foot_r", Vector((-0.14, 0, 0.04)), Vector((-0.14, -0.12, 0.02))),
        ("thigh_l", Vector((0.13, 0, 0.28)), Vector((0.14, 0, 0.15))),
        ("shin_l", Vector((0.14, 0, 0.15)), Vector((0.14, 0, 0.04))),
        ("foot_l", Vector((0.14, 0, 0.04)), Vector((0.14, -0.12, 0.02))),
    ]


def spore_actions(rig):
    make_action(rig, "idle", 48, {
        1: {"core": {"scale": (1, 1, 1)}},
        25: {"core": {"scale": (1.04, 1.04, 1.12)}, "shell": {"scale": (1.03, 1.03, 1.06)}},
        48: {"core": {"scale": (1, 1, 1)}},
    })
    crawl = {1: {}, 49: {}}
    for frame in range(1, 50, 8):
        wave = math.sin((frame - 1) / 48.0 * math.tau)
        crawl[frame] = {"core": {"location": (0, 0, 0.025 * wave)}}
        for index in range(6):
            crawl[frame]["pseudopod_%d" % index] = {"rotation_euler": (0.35 * wave * (1 if index % 2 == 0 else -1), 0, 0.2 * wave)}
    make_action(rig, "crawl", 49, crawl)
    make_action(rig, "alert", 24, {
        1: {"core": {"scale": (1, 1, 1)}},
        24: {"core": {"scale": (1.12, 1.12, 0.62)}, "shell": {"scale": (1.08, 1.08, 0.72)}},
    })
    make_action(rig, "leap", 24, {
        1: {"core": {"scale": (1.12, 1.12, 0.62)}},
        8: {"core": {"scale": (0.9, 0.9, 1.25)}, "shell": {"scale": (1.1, 1.1, 1.12)}},
        24: {"core": {"scale": (1, 1, 1)}},
    })
    make_action(rig, "land", 24, {
        1: {"core": {"scale": (1.15, 1.15, 0.58)}},
        24: {"core": {"scale": (1, 1, 1)}},
    })
    make_action(rig, "death", 48, {
        1: {"core": {"scale": (1, 1, 1)}},
        48: {"core": {"scale": (1.2, 1.2, 0.12), "location": (0, 0, 0.01)}, "shell": {"scale": (1.15, 1.15, 0.18)}},
    })


def hulking_actions(rig):
    make_action(rig, "idle", 48, {
        1: {"chest": {"rotation_euler": (0, 0, 0)}},
        25: {"chest": {"rotation_euler": (0.025, 0.02, 0)}},
        48: {"chest": {"rotation_euler": (0, 0, 0)}},
    })
    make_action(rig, "walk", 48, {
        1: {"thigh_r": {"rotation_euler": (0.45, 0, 0)}, "thigh_l": {"rotation_euler": (-0.45, 0, 0)}},
        25: {"thigh_r": {"rotation_euler": (-0.45, 0, 0)}, "thigh_l": {"rotation_euler": (0.45, 0, 0)}},
        48: {"thigh_r": {"rotation_euler": (0.45, 0, 0)}, "thigh_l": {"rotation_euler": (-0.45, 0, 0)}},
    })
    make_action(rig, "attack", 72, {
        1: {"upper_arm_r": {"rotation_euler": (0, 0, 0)}},
        26: {"upper_arm_r": {"rotation_euler": (-1.15, 0.1, -0.35)}, "forearm_r": {"rotation_euler": (-0.55, 0, 0)}, "chest": {"rotation_euler": (0, 0, -0.25)}},
        38: {"upper_arm_r": {"rotation_euler": (1.35, 0, 0.45)}, "forearm_r": {"rotation_euler": (0.65, 0, 0)}, "chest": {"rotation_euler": (0.22, 0, 0.28)}},
        48: {"upper_arm_r": {"rotation_euler": (1.35, 0, 0.45)}, "chest": {"rotation_euler": (0.22, 0, 0.28)}},
        72: {"upper_arm_r": {"rotation_euler": (0, 0, 0)}, "forearm_r": {"rotation_euler": (0, 0, 0)}, "chest": {"rotation_euler": (0, 0, 0)}},
    })
    make_action(rig, "death", 72, {
        1: {"hips": {"rotation_euler": (0, 0, 0), "location": (0, 0, 0)}},
        72: {"hips": {"rotation_euler": (1.35, 0, 0), "location": (0, 0, -0.45)}, "upper_arm_r": {"rotation_euler": (0.8, 0, 0)}},
    })


def main():
    kind, source, output, preview = sys.argv[sys.argv.index("--") + 1:]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=source)
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    if len(meshes) != 1:
        raise RuntimeError("expected one enemy mesh")
    mesh = meshes[0]
    if kind == "hulking":
        mesh.scale = (2.65, 2.65, 2.65)
    bpy.ops.object.select_all(action="DESELECT")
    mesh.select_set(True)
    bpy.context.view_layer.objects.active = mesh
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    decimate = mesh.modifiers.new("RealtimeBudget", "DECIMATE")
    decimate.ratio = 0.01
    bpy.ops.object.modifier_apply(modifier=decimate.name)
    specs = spore_bones() if kind == "spore" else hulking_bones()
    rig = create_rig(kind, specs)
    rig.animation_data_create()
    bind(mesh, rig, specs)
    if kind == "spore":
        spore_actions(rig)
    else:
        hulking_actions(rig)
    bpy.context.scene.frame_set(1)
    bpy.ops.object.select_all(action="DESELECT")
    mesh.select_set(True)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    os.makedirs(os.path.dirname(output), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=output, export_format="GLB", export_yup=True,
                              export_apply=False, export_animations=True,
                              export_animation_mode="NLA_TRACKS", export_skins=True,
                              export_rest_position_armature=True, export_anim_slide_to_zero=True)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "TEXTURE"
    scene.display.shading.show_cavity = True
    scene.render.resolution_x = 900
    scene.render.resolution_y = 900
    scene.render.resolution_percentage = 100
    cam_data = bpy.data.cameras.new("Preview")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 1.8 if kind == "spore" else 2.8
    cam = bpy.data.objects.new("Preview", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    target = Vector((0, 0, 0.15 if kind == "spore" else 1.1))
    cam.location = Vector((2.2, -3.2, 1.4 if kind == "spore" else 2.0))
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    action_name = "crawl" if kind == "spore" else "attack"
    action = bpy.data.actions.get(action_name)
    rig.animation_data.action = action
    scene.frame_set(25 if kind == "spore" else 38)
    os.makedirs(os.path.dirname(preview), exist_ok=True)
    scene.render.filepath = preview
    bpy.ops.render.render(write_still=True)
    report = {"kind": kind, "output": output, "bones": len(specs),
              "clips": [track.name for track in rig.animation_data.nla_tracks],
              "vertices": len(mesh.data.vertices), "polygons": len(mesh.data.polygons),
              "dimensions": list(mesh.dimensions), "preview": preview}
    with open(os.path.splitext(output)[0] + "_report.json", "w", encoding="utf-8") as handle:
        json.dump(report, handle, ensure_ascii=False, indent=2)
    print("ENEMY_RIG", json.dumps(report, ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()
