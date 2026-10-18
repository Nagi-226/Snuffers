# iso_sets.py — 按「三角面数指纹」指定分量集合，做隔离/补集渲染（分析用，非交付）
# 用法: blender.exe -b --factory-startup --python-exit-code 1 --python iso_sets.py -- <in.glb> <outdir> <spec.json>
# spec.json: {"sets": {"名字": [tris1, tris2, ...]}, "views": {...}}
# 说明: 用 tris 计数当指纹（同一模型内唯一），避免依赖分量枚举顺序；只读取几何，不做任何修改。
import json
import os
import sys

import bpy
from mathutils import Vector

VIEW_DIRS = {
    "side": Vector((1.0, -0.05, 0.05)),
    "grip34": Vector((0.9, -0.75, -0.85)),
    "front34": Vector((0.9, 1.0, -0.55)),
    "front_on": Vector((0.0, 1.0, 0.08)),
    "top34": Vector((0.6, -0.5, 1.0)),
}


def parse_args():
    argv = sys.argv
    argv = argv[argv.index("--") + 1:] if "--" in argv else []
    if len(argv) < 3:
        raise SystemExit("ERR 需要 <in.glb> <outdir> <spec.json>")
    return os.path.abspath(argv[0]), os.path.abspath(argv[1]), os.path.abspath(argv[2])


def component_stats(me):
    n = len(me.vertices)
    parent = list(range(n))

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    for e in me.edges:
        ra, rb = find(e.vertices[0]), find(e.vertices[1])
        if ra != rb:
            parent[ra] = rb
    roots = [find(i) for i in range(n)]
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
    return roots, stats


def main():
    src, outdir, spec_path = parse_args()
    with open(spec_path, encoding="utf-8") as fh:
        spec = json.load(fh)
    os.makedirs(outdir, exist_ok=True)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=src)
    obj = [o for o in bpy.context.scene.objects if o.type == "MESH"][0]
    me = obj.data
    roots, stats = component_stats(me)
    by_tris = {}
    for r, st in stats.items():
        by_tris.setdefault(st["tris"], []).append(r)

    scene = bpy.context.scene
    world = bpy.data.worlds.new("w")
    world.use_nodes = False
    world.color = (1.0, 1.0, 1.0)
    scene.world = world
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.render.resolution_x = 1300
    scene.render.resolution_y = 900
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

    white = bpy.data.materials.new(name="invisible_white")
    white.diffuse_color = (1.0, 1.0, 1.0, 1.0)
    red = bpy.data.materials.new(name="hit_red")
    red.diffuse_color = (0.90, 0.02, 0.02, 1.0)
    blue = bpy.data.materials.new(name="other_blue")
    blue.diffuse_color = (0.55, 0.58, 0.62, 1.0)
    me.materials.clear()
    me.materials.append(white)   # slot 0 其余（隐形）
    me.materials.append(red)     # slot 1 目标集合
    me.materials.append(blue)    # slot 2 补集高亮（用 complement 模式时）

    all_hit = set()
    for name, tris_list in spec["sets"].items():
        sel = set()
        missing = []
        for t in tris_list:
            hit = by_tris.get(t)
            if not hit:
                missing.append(t)
                continue
            sel |= set(hit)
        all_hit |= sel
        if missing:
            print("ISO: %s 未匹配 tris=%s" % (name, missing), flush=True)
        tris = sum(stats[r]["tris"] for r in sel)
        lo = [round(min(stats[r]["lo"][k] for r in sel), 5) for k in range(3)] if sel else None
        hi = [round(max(stats[r]["hi"][k] for r in sel), 5) for k in range(3)] if sel else None
        print("ISO: %-10s 分量=%2d 三角面=%6d bbox=%s..%s"
              % (name, len(sel), tris, lo, hi), flush=True)
        spec["sets"][name] = {"roots": sorted(sel), "tris": tris,
                              "components": len(sel), "bbox_min": lo, "bbox_max": hi}

        for vname in spec.get("views", {}).get(name, ["side"]):
            d = VIEW_DIRS[vname].normalized()
            centre = Vector([(lo[k] + hi[k]) / 2 for k in range(3)])
            psize = max(hi[k] - lo[k] for k in range(3))
            cam_data.ortho_scale = max(psize * 1.25, 0.08)
            cam.location = centre + d * 3.0
            cam.rotation_euler = (centre - cam.location).to_track_quat("-Z", "Y").to_euler()
            for poly in me.polygons:
                poly.material_index = 1 if roots[poly.vertices[0]] in sel else 0
            scene.render.filepath = os.path.join(outdir, "iso_%s_%s.png" % (name, vname))
            bpy.ops.render.render(write_still=True)

    # 补集：留白目标集合，其余涂灰蓝（检查机体是否被拆出洞）
    for name in spec.get("complements", []):
        sel = set(spec["sets"][name]["roots"])
        for poly in me.polygons:
            poly.material_index = 0 if roots[poly.vertices[0]] in sel else 2
        lo = Vector((1e9,) * 3)
        hi = Vector((-1e9,) * 3)
        for r, st in stats.items():
            if r in sel:
                continue
            for k in range(3):
                lo[k] = min(lo[k], st["lo"][k])
                hi[k] = max(hi[k], st["hi"][k])
        centre = (lo + hi) * 0.5
        size = hi - lo
        for vname in ("side", "grip34"):
            d = VIEW_DIRS[vname].normalized()
            cam_data.ortho_scale = max(max(size) * 1.15, 0.1)
            cam.location = centre + d * 3.0
            cam.rotation_euler = (centre - cam.location).to_track_quat("-Z", "Y").to_euler()
            scene.render.filepath = os.path.join(outdir, "rest_%s_%s.png" % (name, vname))
            bpy.ops.render.render(write_still=True)

    with open(os.path.join(outdir, "iso_sets.json"), "w", encoding="utf-8") as fh:
        json.dump({"source": src, "sets": spec["sets"],
                   "total_tris": sum(st["tris"] for st in stats.values()),
                   "total_components": len(stats)}, fh, ensure_ascii=False, indent=1)
    print("ISO: DONE 总分量=%d" % len(stats), flush=True)


main()
