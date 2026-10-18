# render_views.py — 转面渲染探针（只读，用于确认朝向/部件布局）
# 用法: blender.exe -b --factory-startup --python-exit-code 1 --python render_views.py -- <in.glb> <outdir>
import bpy
import json
import os
import sys

from mathutils import Vector


def log(msg):
    print("RENDER: %s" % msg, flush=True)


def parse_args():
    argv = sys.argv
    argv = argv[argv.index("--") + 1:] if "--" in argv else []
    if len(argv) < 2:
        raise SystemExit("RENDER_ERR 需要 <in.glb> <outdir>")
    return os.path.abspath(argv[0]), os.path.abspath(argv[1])


def scene_bounds():
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for obj in bpy.context.scene.objects:
        if obj.type != "MESH":
            continue
        for corner in obj.bound_box:
            w = obj.matrix_world @ Vector(corner)
            for i in range(3):
                lo[i] = min(lo[i], w[i])
                hi[i] = max(hi[i], w[i])
    return lo, hi


def main():
    src, outdir = parse_args()
    os.makedirs(outdir, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=src)
    log("导入完成 %s" % os.path.basename(src))

    lo, hi = scene_bounds()
    center = (lo + hi) * 0.5
    size = hi - lo
    log("BBOX_MIN=%s" % ([round(v, 5) for v in lo],))
    log("BBOX_MAX=%s" % ([round(v, 5) for v in hi],))
    log("SIZE=%s CENTER=%s" % (
        [round(v, 5) for v in size], [round(v, 5) for v in center]))

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.render.resolution_x = 960
    scene.render.resolution_y = 640
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = False
    shading = scene.display.shading
    shading.light = "STUDIO"
    shading.color_type = "TEXTURE"
    shading.show_cavity = True
    shading.show_object_outline = True

    cam_data = bpy.data.cameras.new("probe_cam")
    cam_data.type = "ORTHO"
    cam = bpy.data.objects.new("probe_cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam

    max_dim = max(size)
    cam_data.ortho_scale = max_dim * 1.15
    dist = max_dim * 2.5

    views = {
        "view_pos_x": Vector((1, 0, 0)),
        "view_neg_x": Vector((-1, 0, 0)),
        "view_pos_y": Vector((0, 1, 0)),
        "view_neg_y": Vector((0, -1, 0)),
        "view_pos_z": Vector((0, 0.001, 1)),
        "view_three_quarter": Vector((1, -1, 0.6)),
    }
    for name, direction in views.items():
        d = direction.normalized()
        cam.location = center + d * dist
        cam.rotation_euler = (center - cam.location).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = os.path.join(outdir, name + ".png")
        bpy.ops.render.render(write_still=True)
        log("已渲染 %s.png" % name)

    log("DONE")


main()
