# detail_em57p.py — em57p 贴图特写（分析用，判读弹匣接缝与「引针」形态）
# 用法: blender.exe -b --factory-startup --python-exit-code 1 --python detail_em57p.py -- <in.glb> <outdir>
import os
import sys

import bpy
from mathutils import Vector

VIEWS = {
    "front_34": (Vector((0.0, 0.34, 0.02)), Vector((0.9, 1.0, -0.55)), 0.34),
    "front_on": (Vector((0.0, 0.42, 0.02)), Vector((0.0, 1.0, 0.06)), 0.30),
    "front_side": (Vector((0.0, 0.30, 0.01)), Vector((1.0, 0.05, 0.0)), 0.36),
    "grip_side": (Vector((0.0, -0.235, -0.19)), Vector((1.0, -0.08, 0.05)), 0.30),
    "grip_34": (Vector((0.0, -0.26, -0.20)), Vector((0.9, -0.75, -0.85)), 0.32),
    "optic_34": (Vector((0.0, -0.03, 0.21)), Vector((0.85, -0.75, 0.55)), 0.22),
}


def parse_args():
    argv = sys.argv
    argv = argv[argv.index("--") + 1:] if "--" in argv else []
    if len(argv) < 2:
        raise SystemExit("ERR 需要 <in.glb> <outdir>")
    return os.path.abspath(argv[0]), os.path.abspath(argv[1])


def main():
    src, outdir = parse_args()
    os.makedirs(outdir, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=src)
    obj = [o for o in bpy.context.scene.objects if o.type == "MESH"][0]

    world = bpy.data.worlds.new("w")
    world.use_nodes = False
    world.color = (1.0, 1.0, 1.0)
    scene = bpy.context.scene
    scene.world = world
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.render.resolution_x = 1200
    scene.render.resolution_y = 900
    shading = scene.display.shading
    shading.light = "STUDIO"
    shading.color_type = "TEXTURE"
    shading.show_cavity = True
    shading.cavity_type = "BOTH"
    shading.show_object_outline = False
    scene.view_settings.view_transform = "Standard"

    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "PERSP"
    cam_data.lens = 85.0
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam

    for name, (target, d, oscale) in VIEWS.items():
        d = Vector(d).normalized()
        cam.location = target + d * 0.55
        cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
        cam_data.angle = 2.0 * Vector((1.0, 0.0)).angle(Vector((1.0, 0.0)))
        cam_data.lens = 85.0
        # 用正交近似固定取景，避免透视距离难以估算
        cam_data.type = "ORTHO"
        cam_data.ortho_scale = oscale
        scene.render.filepath = os.path.join(outdir, "detail_%s.png" % name)
        bpy.ops.render.render(write_still=True)
        print("DT: %s ok" % name, flush=True)
    print("DT: DONE", flush=True)


main()
