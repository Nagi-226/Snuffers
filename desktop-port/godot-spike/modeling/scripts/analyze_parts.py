# analyze_parts.py — 部件识别与隔离验证探针（分析用，非交付）
# 用法: blender.exe -b --factory-startup --python-exit-code 1 --python analyze_parts.py -- <in.glb> <outdir>
# 产出: parts_hypothesis.json（各部件命中分量清单与实测三角面）+ 隔离渲染图
# 方法: 机体=白（与白底同色→隐形），目标部件=红，逐个部件单独渲染，肉眼确认拆分是否干净完整。
import bpy
import json
import os
import sys

from mathutils import Vector

# 朝向约定实测：枪口/枪管端 = +Y，枪托端 = -Y，上 = +Z
MAG_MIN_Z = -0.05        # 弹匣整体位于机匣下方
MAG_Y_RANGE = (-0.10, 0.13)
OPTIC_MIN_Z = 0.125      # 瞄具整体位于顶部导轨之上（导轨顶面实测 0.1328）
OPTIC_Y_RANGE = (-0.05, 0.10)   # 只取红点镜，排除前后机械照门
GL_MIN_CY = 0.10         # 下挂榴弹模块位于前段
GL_MAX_Z = 0.04          # 且整体低于枪膛高度


def log(msg):
    print("PARTS: %s" % msg, flush=True)


def parse_args():
    argv = sys.argv
    argv = argv[argv.index("--") + 1:] if "--" in argv else []
    if len(argv) < 2:
        raise SystemExit("PARTS_ERR 需要 <in.glb> <outdir>")
    return os.path.abspath(argv[0]), os.path.abspath(argv[1])


def component_ids(mesh):
    n = len(mesh.vertices)
    parent = list(range(n))

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    for e in mesh.edges:
        a, b = e.vertices
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[ra] = rb
    return [find(i) for i in range(n)]


def component_stats(me, roots):
    stats = {}
    for poly in me.polygons:
        r = roots[poly.vertices[0]]
        st = stats.setdefault(r, {"tris": 0, "verts": 0,
                                  "lo": [1e9, 1e9, 1e9], "hi": [-1e9, -1e9, -1e9]})
        st["tris"] += len(poly.vertices) - 2
        for vi in poly.vertices:
            v = me.vertices[vi]
            for k in range(3):
                st["lo"][k] = min(st["lo"][k], v.co[k])
                st["hi"][k] = max(st["hi"][k], v.co[k])
    # 顶点数按分量去重统计
    seen = {}
    for v in me.vertices:
        r = roots[v.index]
        seen[r] = seen.get(r, 0) + 1
    for r, st in stats.items():
        st["verts"] = seen.get(r, 0)
    return stats


def classify(stats):
    magazine, optic, gl_module = [], [], []
    for r, st in stats.items():
        lo, hi = st["lo"], st["hi"]
        cy = (lo[1] + hi[1]) * 0.5
        if lo[2] > OPTIC_MIN_Z and OPTIC_Y_RANGE[0] < cy < OPTIC_Y_RANGE[1]:
            optic.append(r)
        elif hi[2] < MAG_MIN_Z and MAG_Y_RANGE[0] < cy < MAG_Y_RANGE[1]:
            magazine.append(r)
        elif cy > GL_MIN_CY and hi[2] < GL_MAX_Z:
            gl_module.append(r)
    return magazine, optic, gl_module


def summarize(name, roots_list, stats):
    tris = sum(stats[r]["tris"] for r in roots_list)
    if roots_list:
        lo = [round(min(stats[r]["lo"][k] for r in roots_list), 5) for k in range(3)]
        hi = [round(max(stats[r]["hi"][k] for r in roots_list), 5) for k in range(3)]
    else:
        lo = hi = None
    log("  %-10s 分量=%3d 三角面=%7d bbox=%s..%s" % (name, len(roots_list), tris, lo, hi))
    return {"name": name, "components": len(roots_list), "tris": tris,
            "bbox_min": lo, "bbox_max": hi, "roots": sorted(roots_list)}


def main():
    src, outdir = parse_args()
    os.makedirs(outdir, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=src)
    objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    obj = objs[0]
    me = obj.data
    roots = component_ids(me)
    stats = component_stats(me, roots)
    log("分量总数=%d 总三角面=%d" % (len(stats), sum(s["tris"] for s in stats.values())))

    magazine, optic, gl_module = classify(stats)
    taken = set(magazine) | set(optic) | set(gl_module)
    body = [r for r in stats if r not in taken]

    out = {"source": src,
           "total_components": len(stats),
           "total_tris": sum(s["tris"] for s in stats.values()),
           "parts": [summarize("body", body, stats),
                     summarize("magazine", magazine, stats),
                     summarize("optic", optic, stats),
                     summarize("gl_module", gl_module, stats)]}
    with open(os.path.join(outdir, "parts_hypothesis.json"), "w", encoding="utf-8") as fh:
        json.dump(out, fh, ensure_ascii=False, indent=1)

    part_slot = {}
    me.materials.clear()
    white = bpy.data.materials.new(name="invisible_white")
    white.diffuse_color = (1.0, 1.0, 1.0, 1.0)
    me.materials.append(white)
    red = bpy.data.materials.new(name="highlight_red")
    red.diffuse_color = (0.9, 0.02, 0.02, 1.0)
    me.materials.append(red)

    slot_of = {}
    for r in body:
        slot_of[r] = 0
    for r in taken:
        slot_of[r] = 1

    world = bpy.data.worlds.new("probe_world")
    world.use_nodes = False
    world.color = (1.0, 1.0, 1.0)
    scene = bpy.context.scene
    scene.world = world
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.render.resolution_x = 1100
    scene.render.resolution_y = 800
    scene.render.film_transparent = False
    shading = scene.display.shading
    shading.light = "FLAT"
    shading.color_type = "MATERIAL"
    shading.show_object_outline = False
    scene.view_settings.view_transform = "Standard"

    cam_data = bpy.data.cameras.new("probe_cam")
    cam_data.type = "ORTHO"
    cam = bpy.data.objects.new("probe_cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam

    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for corner in obj.bound_box:
        w = obj.matrix_world @ Vector(corner)
        for k in range(3):
            lo[k] = min(lo[k], w[k])
            hi[k] = max(hi[k], w[k])
    center = (lo + hi) * 0.5
    size = hi - lo
    cam_data.ortho_scale = max(size) * 1.1
    dist = max(size) * 3.0

    views = {
        "side": Vector((1, -0.05, 0.05)),
        "under_front": Vector((0.8, 0.75, -0.7)),
    }
    from collections import Counter
    tri_by_root = {r: stats[r]["tris"] for r in stats}
    order = sorted(stats, key=lambda r: -tri_by_root[r])
    rank = {r: i for i, r in enumerate(order)}
    groups = {"body": body, "magazine": magazine, "optic": optic, "gl_module": gl_module}
    for gname, roots_list in groups.items():
        sel = set(roots_list)
        uniq = sorted({rank[r] for r in roots_list})
        with open(os.path.join(outdir, "iso_%s_ranks.txt" % gname), "w",
                  encoding="utf-8") as fh:
            fh.write(",".join(str(x) for x in uniq))
        # 按部件自身包围盒取景，保证特写足够大
        if roots_list:
            plo = Vector([min(stats[r]["lo"][k] for r in roots_list) for k in range(3)])
            phi = Vector([max(stats[r]["hi"][k] for r in roots_list) for k in range(3)])
        else:
            plo, phi = lo.copy(), hi.copy()
        pcenter = (plo + phi) * 0.5
        psize = phi - plo
        cam_data.ortho_scale = max(max(psize), 0.05) * 1.25
        for vname, direction in views.items():
            for poly in me.polygons:
                r = roots[poly.vertices[0]]
                poly.material_index = 1 if r in sel else 0
            d = direction.normalized()
            cam.location = pcenter + d * dist
            cam.rotation_euler = (pcenter - cam.location).to_track_quat("-Z", "Y").to_euler()
            scene.render.filepath = os.path.join(outdir, "iso_%s_%s.png" % (gname, vname))
            bpy.ops.render.render(write_still=True)
        log("隔离渲染完成 %s（分量=%d 三角面=%d）"
            % (gname, len(roots_list), sum(tri_by_root[r] for r in roots_list)))

    log("DONE")


main()
