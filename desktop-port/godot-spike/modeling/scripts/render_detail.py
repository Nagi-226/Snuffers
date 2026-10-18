# render_detail.py — 局部特写渲染（分析用）：确认下挂模块与瞄具的真实形态
# 用法: blender.exe -b --factory-startup --python-exit-code 1 --python render_detail.py -- <in.glb> <outdir>
import bpy
import os
import sys

from mathutils import Vector

# 特写预设：tag / 相机方向（由目标指向相机）/ 注视点 / 正交尺度 / 分辨率
PRESETS = [
    ("detail_underbarrel_34", (0.9, 0.55, -0.75), (0.0, 0.27, -0.01), 0.42, (1200, 900)),
    ("detail_underbarrel_bottom", (0.02, 0.0, -1.0), (0.0, 0.25, -0.02), 0.45, (1200, 900)),
    ("detail_underbarrel_front", (0.35, 1.0, -0.15), (0.0, 0.36, -0.01), 0.30, (1200, 900)),
    ("detail_top_optic_34", (0.9, -0.7, 0.75), (0.0, 0.03, 0.16), 0.30, (1200, 900)),
    ("detail_top_optic_side", (1.0, -0.05, 0.18), (0.02, 0.02, 0.15), 0.38, (1200, 900)),
]


def log(msg):
    print("DETAIL: %s" % msg, flush=True)


def parse_args():
    argv = sys.argv
    argv = argv[argv.index("--") + 1:] if "--" in argv else []
    if len(argv) < 2:
        raise SystemExit("DETAIL_ERR 需要 <in.glb> <outdir>")
    return os.path.abspath(argv[0]), os.path.abspath(argv[1])


def main():
    src, outdir = parse_args()
    os.makedirs(outdir, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=src)
    log("导入完成")

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.render.film_transparent = False
    scene.render.resolution_percentage = 100
    shading = scene.display.shading
    shading.light = "STUDIO"
    shading.color_type = "TEXTURE"
    shading.show_cavity = True
    shading.show_object_outline = True
    scene.view_settings.view_transform = "Standard"

    cam_data = bpy.data.cameras.new("detail_cam")
    cam_data.type = "ORTHO"
    cam = bpy.data.objects.new("detail_cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam

    for tag, direction, center, scale, res in PRESETS:
        scene.render.resolution_x = res[0]
        scene.render.resolution_y = res[1]
        c = Vector(center)
        d = Vector(direction).normalized()
        cam_data.ortho_scale = scale
        cam.location = c + d * 3.0
        cam.rotation_euler = (c - cam.location).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = os.path.join(outdir, tag + ".png")
        bpy.ops.render.render(write_still=True)
        log("已渲染 %s.png" % tag)

    log("DONE")


main()
