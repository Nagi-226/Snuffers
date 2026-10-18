# highlight_rules.py — 规则假设高亮 + 隔离验证（分析用，非交付）
# 用法: blender.exe -b --factory-startup --python-exit-code 1 --python highlight_rules.py -- <in.glb> <outdir>
# 两段产出:
#   1) hl_<view>.png  —— 多规则同图着色（灰=其余），看规则是否命中目标区域
#   2) iso_<rule>_<view>.png —— 单规则隔离（白=其余，与白底同色隐形），看该集合本身是不是一个完整部件
# 目的: 在单材质模型上用「连通分量 + 空间位置」逐步收敛弹匣/瞄具/引针的阈值，全程不碰几何。
import json
import os
import sys

import bpy
from mathutils import Vector

# (名称, 颜色, 判定 lambda(lo, hi, cy, cx))
RULES = [
    ("low", (0.92, 0.10, 0.55), lambda lo, hi, cy, cx: hi[2] < -0.115),
    ("optic", (0.10, 0.75, 0.25),
     lambda lo, hi, cy, cx: lo[2] > 0.13 and -0.16 < cy < 0.06),
    ("front_low", (0.10, 0.35, 0.92), lambda lo, hi, cy, cx: cy > 0.20 and hi[2] < 0.06),
    ("rear_top", (0.95, 0.85, 0.10), lambda lo, hi, cy, cx: cy < -0.16 and lo[2] > 0.13),
]
VIEWS_COMBINED = {
    "side": (Vector((1, -0.05, 0.05)), 1.08),
    "front": (Vector((0, 1, 0.12)), 0.9),
    "bottom": (Vector((0.02, -0.25, -1)), 1.0),
    "grip34": (Vector((1, -1.1, -0.75)), 0.40),
}
ISO_VIEWS = {
    "side": (Vector((1, -0.05, 0.05)), 1.25),
    "front": (Vector((0, 1, 0.12)), 1.25),
    "grip34": (Vector((1, -1.1, -0.75)), 1.25),
}


def log(msg):
    print("HL: %s" % msg, flush=True)


def parse_args():
    argv = sys.argv
    argv = argv[argv.index("--") + 1:] if "--" in argv else []
    if len(argv) < 2:
        raise SystemExit("HL_ERR 需要 <in.glb> <outdir>")
    return os.path.abspath(argv[0]), os.path.abspath(argv[1])


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


def setup_scene(obj):
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
    return cam, cam_data, (lo + hi) * 0.5, hi - lo


def render_views(cam, cam_data, target, size, views, prefix, bbox_scale=1.0):
    dist = max(size) * 3.0
    for vname, (d, oscale) in views.items():
        cam_data.ortho_scale = max(size) * oscale * bbox_scale
        d = Vector(d).normalized()
        cam.location = target + d * dist
        cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
        bpy.context.scene.render.filepath = os.path.join(OUTDIR, "%s_%s.png" % (prefix, vname))
        bpy.ops.render.render(write_still=True)


def main():
    global OUTDIR
    src, outdir = parse_args()
    OUTDIR = outdir
    os.makedirs(outdir, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=src)
    obj = [o for o in bpy.context.scene.objects if o.type == "MESH"][0]
    me = obj.data
    roots = component_ids(me)
    stats = component_stats(me, roots)
    order = sorted(stats, key=lambda r: -stats[r]["tris"])
    cam, cam_data, center, size = setup_scene(obj)

    sets = {}
    for name, col, pred in RULES:
        hit = [r for r in order
               if pred(stats[r]["lo"], stats[r]["hi"],
                       (stats[r]["lo"][1] + stats[r]["hi"][1]) * 0.5,
                       (stats[r]["lo"][0] + stats[r]["hi"][0]) * 0.5)]
        sets[name] = {"hit": hit, "color": col}
        tris = sum(stats[r]["tris"] for r in hit)
        lo = [round(min(stats[r]["lo"][k] for r in hit), 5) for k in range(3)] if hit else None
        hi = [round(max(stats[r]["hi"][k] for r in hit), 5) for k in range(3)] if hit else None
        log("规则 %-10s 分量=%3d 三角面=%7d bbox=%s..%s"
            % (name, len(hit), tris, lo, hi))
        sets[name]["summary"] = {"components": len(hit), "tris": tris,
                                 "bbox_min": lo, "bbox_max": hi}

    # ---------- 第一段：多规则同图 ----------
    me.materials.clear()
    mats = [bpy.data.materials.new(name="rest_grey")]
    mats[0].diffuse_color = (0.78, 0.78, 0.78, 1.0)
    me.materials.append(mats[0])
    slot_of = {}
    for idx, (name, col, _) in enumerate(RULES):
        m = bpy.data.materials.new(name="rule_%s" % name)
        m.diffuse_color = (col[0], col[1], col[2], 1.0)
        me.materials.append(m)
        for r in sets[name]["hit"]:
            slot_of[r] = idx + 1
    for poly in me.polygons:
        poly.material_index = slot_of.get(roots[poly.vertices[0]], 0)
    render_views(cam, cam_data, center, size, VIEWS_COMBINED, "hl")

    # ---------- 第二段：逐集合隔离 + 机体隔离 ----------
    white = bpy.data.materials.new(name="invisible_white")
    white.diffuse_color = (1.0, 1.0, 1.0, 1.0)
    red = bpy.data.materials.new(name="hit_red")
    red.diffuse_color = (0.90, 0.02, 0.02, 1.0)
    me.materials.clear()
    me.materials.append(white)
    me.materials.append(red)

    iso_targets = dict(sets)
    all_hit = set()
    for name in sets:
        all_hit |= set(sets[name]["hit"])
    complement = [r for r in order if r not in all_hit]
    iso_targets["body_only"] = {"hit": complement,
                                "summary": {"components": len(complement),
                                            "tris": sum(stats[r]["tris"] for r in complement),
                                            "bbox_min": None, "bbox_max": None}}
    for name, info in iso_targets.items():
        sel = set(info["hit"])
        for poly in me.polygons:
            poly.material_index = 1 if roots[poly.vertices[0]] in sel else 0
        if info["hit"]:
            plo = Vector([min(stats[r]["lo"][k] for r in info["hit"]) for k in range(3)])
            phi = Vector([max(stats[r]["hi"][k] for r in info["hit"]) for k in range(3)])
            target = (plo + phi) * 0.5
            psize = phi - plo
            pscale = max(max(psize), 0.08)
        else:
            target, pscale = center, max(size)
        render_views(cam, cam_data, target, Vector((pscale, pscale, pscale)),
                     ISO_VIEWS, "iso_%s" % name, bbox_scale=1.0)

    with open(os.path.join(outdir, "hl_rules.json"), "w", encoding="utf-8") as fh:
        json.dump({"source": src, "total_components": len(stats),
                   "rules": {n: {"summary": sets[n]["summary"], "roots": sets[n]["hit"]}
                             for n in sets},
                   "body_only": {"summary": iso_targets["body_only"]["summary"]}},
                  fh, ensure_ascii=False, indent=1)
    log("DONE 分量总数=%d" % len(stats))


main()
