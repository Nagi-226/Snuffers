# colorize_components.py — 分量上色诊断（分析用，非交付）
# 用法: blender.exe -b --factory-startup --python-exit-code 1 --python colorize_components.py -- <in.glb> <outdir> [topN]
# 产出: 每个大分量一种高饱和色（其余浅灰）+ legend.json（颜色↔分量↔三角面↔bbox），多视角渲染。
# 目的: 在单材质模型里把「连通分量」映射到肉眼可辨的实体，作为阈值标定的证据。
import json
import os
import sys

import bpy
from mathutils import Vector

PALETTE = [
    (0.95, 0.09, 0.09),   # red
    (0.09, 0.35, 0.95),   # blue
    (0.60, 0.95, 0.09),   # yellow-green
    (0.95, 0.09, 0.85),   # magenta
    (0.09, 0.95, 0.80),   # cyan
    (0.95, 0.55, 0.09),   # orange
    (0.13, 0.09, 0.95),   # indigo
    (0.09, 0.95, 0.24),   # green
    (0.95, 0.09, 0.38),   # crimson
    (0.55, 0.09, 0.95),   # violet
    (0.09, 0.63, 0.95),   # azure
    (0.85, 0.85, 0.09),   # yellow
]


def log(msg):
    print("COLOR: %s" % msg, flush=True)


def parse_args():
    argv = sys.argv
    argv = argv[argv.index("--") + 1:] if "--" in argv else []
    if len(argv) < 2:
        raise SystemExit("COLOR_ERR 需要 <in.glb> <outdir> [topN]")
    top = int(argv[2]) if len(argv) > 2 else 12
    return os.path.abspath(argv[0]), os.path.abspath(argv[1]), top


def component_ids(me):
    n = len(me.vertices)
    parent = list(range(n))

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    for e in me.edges:
        a, b = e.vertices
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[ra] = rb
    return [find(i) for i in range(n)]


def component_stats(me, roots):
    stats = {}
    for poly in me.polygons:
        r = roots[poly.vertices[0]]
        st = stats.setdefault(r, {"tris": 0, "lo": [1e9] * 3, "hi": [-1e9] * 3})
        st["tris"] += len(poly.vertices) - 2
        for vi in poly.vertices:
            co = me.vertices[vi].co
            for k in range(3):
                st["lo"][k] = min(st["lo"][k], co[k])
                st["hi"][k] = max(st["hi"][k], co[k])
    return stats


def main():
    src, outdir, top_n = parse_args()
    os.makedirs(outdir, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=src)
    obj = [o for o in bpy.context.scene.objects if o.type == "MESH"][0]
    me = obj.data
    roots = component_ids(me)
    stats = component_stats(me, roots)
    order = sorted(stats, key=lambda r: -stats[r]["tris"])
    top = order[:top_n]

    me.materials.clear()
    grey = bpy.data.materials.new(name="rest_grey")
    grey.diffuse_color = (0.72, 0.72, 0.72, 1.0)
    me.materials.append(grey)
    legend = []
    for i, r in enumerate(top):
        col = PALETTE[i % len(PALETTE)]
        mat = bpy.data.materials.new(name="comp_%02d" % i)
        mat.diffuse_color = (col[0], col[1], col[2], 1.0)
        me.materials.append(mat)
        st = stats[r]
        legend.append({
            "color_id": i,
            "slot": i + 1,
            "root": r,
            "rgb": [int(round(c * 255)) for c in col],
            "tris": st["tris"],
            "bbox_min": [round(v, 5) for v in st["lo"]],
            "bbox_max": [round(v, 5) for v in st["hi"]],
            "center": [round((st["lo"][k] + st["hi"][k]) * 0.5, 5) for k in range(3)],
        })
    slot_of = {r: i + 1 for i, r in enumerate(top)}
    for poly in me.polygons:
        poly.material_index = slot_of.get(roots[poly.vertices[0]], 0)

    world = bpy.data.worlds.new("w")
    world.use_nodes = False
    world.color = (1.0, 1.0, 1.0)
    scene = bpy.context.scene
    scene.world = world
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.render.resolution_x = 1400
    scene.render.resolution_y = 900
    scene.render.film_transparent = False
    shading = scene.display.shading
    shading.light = "FLAT"
    shading.color_type = "MATERIAL"
    shading.show_object_outline = False
    scene.view_settings.view_transform = "Standard"

    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam

    lo = Vector((1e9,) * 3)
    hi = Vector((-1e9,) * 3)
    for c in obj.bound_box:
        w = obj.matrix_world @ Vector(c)
        for k in range(3):
            lo[k] = min(lo[k], w[k])
            hi[k] = max(hi[k], w[k])
    center = (lo + hi) * 0.5
    size = hi - lo
    dist = max(size) * 3.0

    views = {
        "side": (Vector((1, -0.05, 0.05)), max(size) * 1.08),
        "bottom": (Vector((0, -0.2, -1)), max(size) * 1.08),
        "front": (Vector((0, 1, 0.12)), max(size) * 0.85),
        "grip34": (Vector((1, -1.1, -0.75)), 0.42),
    }
    for vname, (d, oscale) in views.items():
        cam_data.ortho_scale = oscale
        d = Vector(d).normalized()
        target = center if vname != "grip34" else Vector((0.0, -0.246, -0.14))
        cam.location = target + d * dist
        cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = os.path.join(outdir, "colors_%s.png" % vname)
        bpy.ops.render.render(write_still=True)
        log("已渲染 %s（ortho=%.3f）" % (vname, oscale))

    with open(os.path.join(outdir, "legend.json"), "w", encoding="utf-8") as fh:
        json.dump({"source": src, "top_n": top_n, "total_components": len(stats),
                   "components": legend}, fh, ensure_ascii=False, indent=1)
    log("DONE 分量总数=%d 上色=%d" % (len(stats), top_n))


main()
