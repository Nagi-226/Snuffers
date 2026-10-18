"""weapon_postprocess.py — 武器 GLB 后处理：原样保管 + 结构化拆分（通用管线）。

## 为什么这样做（设计约束，来自 W9 派单 2026-10-18 第 14/15 号）
机主已把 AI 图生 3D 产物验收为"完美成品"，因此本脚本**不做任何资产优化**：
- 不做减面/重拓扑/顶点合并/法线重算
- 不重压缩、不重采样贴图
- 只做一件事：把可动/可换装模块（弹匣、瞄具、下挂模块…）从单一网格里按连通分量
  分离成独立子对象，以便换弹、换镜、挂件等动画/挂点需求；其余几何全部留在机体对象里。

拆分只允许"分组/分离已有几何"：分离按连通分量整块搬移，不增删改任何顶点与 UV。

## 第 17 号单新增：弹匣枢轴原点
对 PROFILES 里带 `pivot_part` 的武器，拆分后把该部件的**对象原点**迁到"部件顶面
（世界 +Z 最高面）的面积加权中心"，供换弹动画以此点为枢轴做拔插/旋转。
只动原点不动世界几何：脚本内用世界坐标量化哈希（1 nm 网格）逐对象自证零位移；
导出后该平移量即 glTF 节点的 `translation`，Godot 侧即 MeshInstance3D 的变换原点。

## 通用化方式
不同武器的尺寸与布局差异很大（EM-68A 全枪 1.0 m 长、EM-57P 手枪握把内藏弹匣），
因此**部件划分规则按武器分档**（见 PROFILES）：每档一套 classify() + 部件名单，
阈值一律来自隔离渲染实测，禁止跨武器套用。拆分/自检/导出逻辑对所有武器共用。

## 用法
    blender.exe -b --python weapon_postprocess.py -- <输入.glb> [输出.glb] [报告.json]
默认为与输入同目录的：<武器名>_viewmodel.glb
  + em68a → weapon_postprocess_report.json（沿用首单路径）
  + 其他  → weapon_postprocess_report_<武器名>.json

## 验收自检（脚本内直接物化）
导出 GLB 与输入 GLB 的三角面数/顶点数逐一相等（文件级实测，非估算），否则以非零码退出。
"""

import bpy
import bmesh
import hashlib
import json
import os
import struct
import sys
import time

# ---------------------------------------------------------------- 常量

GLB_MAGIC = 0x46546C67
CHUNK_JSON = 0x4E4F534A
CHUNK_BIN = 0x004E4942


# ---------------------------------------------------------------- 每把武器的部件划分规则
# 坐标系：米；枪口 +Y、枪托 -Y、上 +Z。
# 判定顺序：瞄具 → 弹匣 → 附加模块 → 其余归 body（顺序影响重叠区域归属）。
# 阈值必须逐武器实测标定（渲染"规则高亮 → 逐集合隔离"两轮验证），禁止跨武器套用。

def _classify_em68a(stats):
    """EM-68A 突击步枪（第 14 号单；已过 L3 审查，阈值冻结）。"""
    labels = {}
    for root, st in stats.items():
        lo, hi = st["lo"], st["hi"]
        cy = (lo[1] + hi[1]) * 0.5
        # 瞄具：整体位于顶部导轨之上（导轨顶面实测 0.1328）；Y 区间只取红点镜，
        # 前后折叠机械照门属机体固定件，不划入瞄具
        if lo[2] > 0.125 and -0.05 < cy < 0.10:
            labels[root] = "optic"
        # 弹匣：整体位于机匣下方
        elif hi[2] < -0.05 and -0.10 < cy < 0.13:
            labels[root] = "magazine"
        # 下挂榴弹模块：位于前段且整体低于枪膛高度
        elif cy > 0.10 and hi[2] < 0.04:
            labels[root] = "gl_module"
        else:
            labels[root] = "body"
    return labels


def _classify_em57p(stats):
    """EM-57P「掣」手枪（第 15 号单）。

    实测要点（详见 weapon_postprocess_report_em57p.md §3）：单材质、181 个连通分量；
    弹匣与握把齐平（无独立插入件几何），故弹匣取"握把下段整块壳体 + 底盖板"，
    拆出后握把侧板/前后握把条仍在，等价于"抽出弹匣后只剩弹匣井"。
    """
    labels = {}
    for root, st in stats.items():
        lo, hi = st["lo"], st["hi"]
        cy = (lo[1] + hi[1]) * 0.5
        # 瞄具：整体高于机匣顶面（实测机匣顶 z≈0.13），且位于镜桥前方到照门之间
        if lo[2] > 0.13 and -0.16 < cy < 0.06:
            labels[root] = "optic"
        # 弹匣：握把下段（整体在 z=-0.145 以下），且落在握把的 Y 区间内
        elif hi[2] < -0.145 and -0.38 <= cy <= -0.14:
            labels[root] = "magazine"
        # 引针模块：前段下挂组件；用"顶面 z>0.01"排除最底部导轨（导轨件顶面 <= 0）
        elif cy > 0.20 and 0.01 < hi[2] < 0.07 and lo[2] > -0.06:
            labels[root] = "laser_module"
        else:
            labels[root] = "body"
    return labels


# pivot_part：该部件的对象原点要迁到"它自身顶面（世界 +Z 最高面）的面积加权中心"，
# 供程序化换弹动画以该点为枢轴做拔插/旋转（第 17 号单）。只动原点，不动世界几何。
#
# file_vertex_delta_allowance：导出 GLB 相对输入 GLB 的**文件级顶点数**允许增量。
#   - em68a：0（实测逐字节相同）
#   - em57p：39 = 13 个平坦面 × 3 角点。原因：输入里这 13 个面不带 smooth 标记，
#     走 glTF 导出的"按面拆角点"路径，而 Blender 侧顶点数仍是 708,475（相等）。
#     该增量与拆分/枢轴无关：零拆分对照实验（只 import→export）同样得 708,514。
#     2026-10-18 蜂后裁决：em57p 以「与自身迁移前比」为口径，+39 列为已知基线。
PROFILES = {
    "em68a": {"parts": ("body", "magazine", "optic", "gl_module"),
              "classify": _classify_em68a, "pivot_part": "magazine",
              "file_vertex_delta_allowance": 0},
    "em57p": {"parts": ("body", "magazine", "optic", "laser_module"),
              "classify": _classify_em57p, "pivot_part": "magazine",
              "file_vertex_delta_allowance": 39,
              "file_vertex_delta_reason": "13 个非平滑面按角点拆分（零拆分对照实验同样 +39）"},
}


def log(msg):
    print("[weapon_postprocess] %s" % msg, flush=True)


def die(msg, code=1):
    print("[weapon_postprocess] FAIL: %s" % msg, flush=True)
    sys.exit(code)


# ---------------------------------------------------------------- GLB 文件级读取

def read_glb(path):
    """解析 GLB 容器，返回 (json_dict, bin_bytes)。只读文件本身，不经过 Blender。"""
    with open(path, "rb") as fh:
        blob = fh.read()
    if len(blob) < 12:
        die("GLB 太短: %s" % path)
    magic, version, total = struct.unpack_from("<III", blob, 0)
    if magic != GLB_MAGIC:
        die("不是 GLB 文件: %s" % path)
    offset = 12
    js = None
    binary = b""
    while offset + 8 <= total:
        clen, ctype = struct.unpack_from("<II", blob, offset)
        offset += 8
        data = blob[offset:offset + clen]
        offset += clen
        if ctype == CHUNK_JSON:
            js = json.loads(data.decode("utf-8"))
        elif ctype == CHUNK_BIN:
            binary = data
    if js is None:
        die("GLB 缺少 JSON chunk: %s" % path)
    return js, binary, len(blob)


def accessor_count(js, index):
    accessors = js.get("accessors") or []
    if index is None or index >= len(accessors):
        return 0
    return int(accessors[index].get("count", 0))


def image_bytes(js, binary, image_index):
    """取出 images[i] 的原始字节（bufferView 内嵌 或 data: URI）。"""
    images = js.get("images") or []
    if image_index >= len(images):
        return None
    img = images[image_index]
    if "bufferView" in img:
        bv = (js.get("bufferViews") or [])[img["bufferView"]]
        start = int(bv.get("byteOffset", 0))
        length = int(bv.get("byteLength", 0))
        return binary[start:start + length]
    uri = img.get("uri", "")
    if uri.startswith("data:") and "," in uri:
        import base64
        return base64.b64decode(uri.split(",", 1)[1])
    return None


def glb_summary(path):
    """文件级实测：每个 primitive 的顶点/三角面 + 材质/贴图清单。"""
    js, binary, file_size = read_glb(path)
    prims = []
    verts_total = 0
    tris_total = 0
    attr_keys = set()
    for mesh in js.get("meshes") or []:
        for prim in mesh.get("primitives") or []:
            attrs = prim.get("attributes") or {}
            n_verts = accessor_count(js, attrs.get("POSITION"))
            if "indices" in prim:
                n_idx = accessor_count(js, prim["indices"])
                n_tris = n_idx // 3
            else:
                n_tris = n_verts // 3
            verts_total += n_verts
            tris_total += n_tris
            for key in attrs:
                attr_keys.add(key)
            prims.append({
                "mesh": mesh.get("name", ""),
                "material": prim.get("material"),
                "mode": prim.get("mode", 4),
                "verts": n_verts,
                "tris": n_tris,
                "attributes": sorted(attrs.keys()),
            })

    images = []
    for i, img in enumerate(js.get("images") or []):
        raw = image_bytes(js, binary, i)
        images.append({
            "name": img.get("name", ""),
            "mime_type": img.get("mimeType", ""),
            "byte_length": len(raw) if raw is not None else 0,
            "sha256": hashlib.sha256(raw).hexdigest() if raw is not None else "",
        })

    materials = []
    for mat in js.get("materials") or []:
        entry = {"name": mat.get("name", ""),
                 "double_sided": bool(mat.get("doubleSided", False)),
                 "alpha_mode": mat.get("alphaMode", "OPAQUE")}
        pbr = mat.get("pbrMetallicRoughness") or {}
        entry["has_base_color_texture"] = "baseColorTexture" in pbr
        entry["has_mr_texture"] = "metallicRoughnessTexture" in pbr
        entry["has_normal_texture"] = "normalTexture" in mat
        entry["has_occlusion_texture"] = "occlusionTexture" in mat
        materials.append(entry)

    return {
        "path": path,
        "file_bytes": file_size,
        "generator": (js.get("asset") or {}).get("generator", ""),
        "version": (js.get("asset") or {}).get("version", ""),
        "nodes": len(js.get("nodes") or []),
        "meshes": len(js.get("meshes") or []),
        "primitives": len(prims),
        "vertices": verts_total,
        "triangles": tris_total,
        "primitive_detail": prims,
        "attribute_keys": sorted(attr_keys),
        "materials": materials,
        "images": images,
        "animations": len(js.get("animations") or []),
        "skins": len(js.get("skins") or []),
        "extensions_used": js.get("extensionsUsed") or [],
    }


# ---------------------------------------------------------------- 网格分析

def component_roots(mesh):
    """并查集求连通分量，返回每个顶点的根 id。"""
    n = len(mesh.vertices)
    parent = list(range(n))

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    for edge in mesh.edges:
        ra, rb = find(edge.vertices[0]), find(edge.vertices[1])
        if ra != rb:
            parent[ra] = rb
    return [find(i) for i in range(n)]


def component_stats(mesh, roots):
    """每个分量的三角面数/顶点数/包围盒（用于识别部件并按实测数据出报告）。"""
    stats = {}
    for poly in mesh.polygons:
        root = roots[poly.vertices[0]]
        st = stats.setdefault(root, {"tris": 0, "verts": 0,
                                     "lo": [1e9, 1e9, 1e9], "hi": [-1e9, -1e9, -1e9]})
        st["tris"] += len(poly.vertices) - 2
        for vi in poly.vertices:
            co = mesh.vertices[vi].co
            for k in range(3):
                st["lo"][k] = min(st["lo"][k], co[k])
                st["hi"][k] = max(st["hi"][k], co[k])
    for v in mesh.vertices:
        root = roots[v.index]
        stats[root]["verts"] += 1
    return stats


# ---------------------------------------------------------------- 拆分

def build_part_groups(obj, mesh, roots, labels, part_names):
    """用顶点组承载部件归属，供后续分多次 separate 时保持标签不丢。"""
    for name in part_names:
        obj.vertex_groups.new(name=name)
    buckets = {name: [] for name in part_names}
    for vi, root in enumerate(roots):
        buckets[labels[root]].append(vi)
    for name, indices in buckets.items():
        if indices:
            obj.vertex_groups[name].add(indices, 1.0, 'REPLACE')
    return buckets


def separate_part(obj, part_name):
    """把指定顶点组对应的几何整块分离成新对象（不增删改任何顶点）。返回新对象。"""
    group = obj.vertex_groups.get(part_name)
    if group is None:
        die("缺少顶点组 %s" % part_name)
    gi = group.index
    selected = [v.index for v in obj.data.vertices
                if any(g.group == gi for g in v.groups)]
    if not selected:
        die("顶点组 %s 为空" % part_name)

    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.context.tool_settings.mesh_select_mode = (True, False, False)
    bm = bmesh.from_edit_mesh(obj.data)
    bm.verts.ensure_lookup_table()
    wanted = set(selected)
    for vert in bm.verts:
        vert.select = vert.index in wanted
    bm.select_flush(False)
    bm.select_flush(True)
    bmesh.update_edit_mesh(obj.data)
    bpy.ops.mesh.separate(type='SELECTED')
    bpy.ops.object.mode_set(mode='OBJECT')

    new_objs = [o for o in bpy.context.selected_objects if o is not obj]
    if len(new_objs) != 1:
        die("separate 期望 1 个新对象，实际 %d" % len(new_objs))
    return new_objs[0]


def strip_vertex_groups(obj):
    while len(obj.vertex_groups) > 0:
        obj.vertex_groups.remove(obj.vertex_groups[0])


# ---------------------------------------------------------------- 主流程

# ---------------------------------------------------------------- 枢轴原点（第 17 号单）
# 目标：把某个部件的**对象原点**迁到"部件自身顶面（世界 +Z 最高的那一面）的面积加权中心"，
# 世界空间几何逐点零变化。做法是 mesh 局部坐标整体平移 -local_pivot，
# 同时对象矩阵右乘 Translation(local_pivot) 补偿：
#     M_new = M_old @ T(local)  ，co_new = co_old - local
#     => M_new @ co_new = M_old @ (co_old - local + local) = M_old @ co_old   （世界坐标不变）
#     => 原点（局部 0）落到世界 M_old @ local = 目标点
# 导出时该 Translation 会写成 glTF 节点的 translation，Godot 侧即 MeshInstance3D 的变换原点。

def world_positions(objects):
    """{对象名: (N,3) float64 世界坐标}，用于迁移前后世界空间守恒自检。"""
    import numpy as np
    out = {}
    for o in objects:
        mw = o.matrix_world
        mats = [list(mw @ v.co) for v in o.data.vertices]
        out[o.name] = np.asarray(mats, dtype=np.float64) if mats else np.zeros((0, 3))
    return out


def top_face_center(obj, band=0.002):
    """返回 (世界坐标目标点, 明细)。顶面 = 世界 +Z 最大处上下 band 米内完全落入的三角形。"""
    import numpy as np
    from mathutils import Vector
    mw = obj.matrix_world
    mesh = obj.data
    mesh.calc_loop_triangles()
    co = np.asarray([list(mw @ v.co) for v in mesh.vertices], dtype=np.float64)
    z_max = float(co[:, 2].max())
    z_cut = z_max - band
    band_vert_idx = np.nonzero(co[:, 2] >= z_cut)[0]
    area_sum = 0.0
    centroid_acc = np.zeros(3, dtype=np.float64)
    tri_in_band = 0
    tri_total = 0
    for tri in mesh.loop_triangles:
        tri_total += 1
        idx = tri.vertices
        p = co[list(idx)]
        if p[:, 2].min() < z_cut:
            continue
        tri_in_band += 1
        a = p[1] - p[0]
        b = p[2] - p[0]
        area = 0.5 * float(np.linalg.norm(np.cross(a, b)))
        if area <= 0.0:
            continue
        area_sum += area
        centroid_acc += area * p.mean(axis=0)
    if area_sum > 0.0:
        point = centroid_acc / area_sum
        method = "顶面三角形面积加权重心（完全落在 z>=z_max-%.4f 的三角形）" % band
    else:
        point = co[band_vert_idx].mean(axis=0)
        method = "顶面顶点算术平均（无完全落入 band 的三角形，退化为顶点均值）"
    info = {
        "method": method,
        "band_m": band,
        "z_max_world": round(z_max, 9),
        "band_vertex_count": int(band_vert_idx.size),
        "triangles_total": int(tri_total),
        "triangles_in_band": int(tri_in_band),
        "top_face_area_m2": round(area_sum, 12),
        "world_point": [round(float(x), 9) for x in point],
    }
    return Vector((float(point[0]), float(point[1]), float(point[2]))), info


def move_origin_to(obj, world_point):
    """把对象原点迁到世界点 world_point，世界空间几何零位移。返回 (前进原点, 后原点)。"""
    from mathutils import Matrix
    mw_before = obj.matrix_world.copy()
    local = mw_before.inverted() @ world_point
    before = list(mw_before.translation)
    obj.data.transform(Matrix.Translation(-local))
    obj.matrix_world = mw_before @ Matrix.Translation(local)
    obj.data.update()
    after = list(obj.matrix_world.translation)
    return before, after


def main():
    started = time.time()
    argv = sys.argv
    argv = argv[argv.index("--") + 1:] if "--" in argv else []
    if not argv:
        die("用法: blender.exe -b --python weapon_postprocess.py -- <in.glb> [out.glb] [report.json]")
    src = os.path.abspath(argv[0])
    if not os.path.isfile(src):
        die("输入不存在: %s" % src)
    stem = os.path.splitext(os.path.basename(src))[0]
    profile = PROFILES.get(stem)
    if profile is None:
        die("没有武器 %r 的部件划分规则；已支持：%s（新增武器须先在 PROFILES 里标定阈值）"
            % (stem, sorted(PROFILES)))
    part_names = profile["parts"]
    prefix = stem + "_"
    default_report = ("weapon_postprocess_report.json" if stem == "em68a"
                      else "weapon_postprocess_report_%s.json" % stem)
    out_glb = os.path.abspath(argv[1]) if len(argv) > 1 else os.path.join(
        os.path.dirname(src), "%s_viewmodel.glb" % stem)
    report_path = os.path.abspath(argv[2]) if len(argv) > 2 else os.path.join(
        os.path.dirname(src), default_report)
    log("输入 %s" % src)
    log("配置 %s → 部件 %s" % (stem, ", ".join(part_names)))
    log("输出 %s" % out_glb)

    report = {
        "script": "weapon_postprocess.py",
        "blender_version": bpy.app.version_string,
        "input": {}, "output": {}, "mesh": {}, "parts": {},
        "pivot": None,
        "comparison": {}, "notes": [],
    }

    # 1) 输入文件级实测（不经过 Blender，测的是文件本身）
    in_summary = glb_summary(src)
    report["input"]["glb"] = in_summary
    log("输入 GLB：triangles=%d vertices=%d meshes=%d primitives=%d materials=%d images=%d"
        % (in_summary["triangles"], in_summary["vertices"], in_summary["meshes"],
           in_summary["primitives"], len(in_summary["materials"]), len(in_summary["images"])))

    # 2) 导入
    bpy.ops.wm.read_factory_settings(use_empty=True)
    t0 = time.time()
    bpy.ops.import_scene.gltf(filepath=src)
    import_secs = round(time.time() - t0, 2)
    mesh_objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    other_objs = [o for o in bpy.context.scene.objects if o.type != "MESH"]
    if len(mesh_objs) != 1:
        die("期望输入为单一网格对象，实际 %d 个" % len(mesh_objs))
    if other_objs:
        die("输入含非网格对象 %s，本脚本仅支持纯网格武器"
            % [o.name for o in other_objs])
    obj = mesh_objs[0]
    mesh = obj.data
    mesh.calc_loop_triangles()
    in_blender = {
        "objects": len(bpy.context.scene.objects),
        "vertices": len(mesh.vertices),
        "polygons": len(mesh.polygons),
        "triangles": len(mesh.loop_triangles),
        "uv_layers": [uv.name for uv in mesh.uv_layers],
        "color_attributes": [c.name for c in mesh.color_attributes],
        "material_slots": [s.material.name if s.material else None
                           for s in obj.material_slots],
        "import_seconds": import_secs,
        "transform": {
            "location": list(obj.location), "rotation_euler": list(obj.rotation_euler),
            "scale": list(obj.scale),
        },
    }
    report["input"]["blender_import"] = in_blender
    report["mesh"] = {
        "uv_layers": in_blender["uv_layers"],
        "color_attributes": in_blender["color_attributes"],
        "shade_smooth_faces": sum(1 for p in mesh.polygons if p.use_smooth),
        "materials": [],
    }
    for mat in bpy.data.materials:
        entry = {"name": mat.name, "node_tree": mat.node_tree is not None,
                 "images": []}
        if mat.node_tree is not None:
            seen = set()
            for node in mat.node_tree.nodes:
                if node.type == "TEX_IMAGE" and node.image is not None:
                    img = node.image
                    if img.name in seen:
                        continue
                    seen.add(img.name)
                    entry["images"].append({
                        "name": img.name,
                        "size": [int(img.size[0]), int(img.size[1])],
                        "packed": bool(img.packed_file),
                        "file_format": img.file_format,
                    })
        report["mesh"]["materials"].append(entry)
    log("Blender 导入：verts=%d polys=%d tris=%d uv=%s"
        % (in_blender["vertices"], in_blender["polygons"], in_blender["triangles"],
           in_blender["uv_layers"]))

    # 3) 连通分量分析
    t0 = time.time()
    roots = component_roots(mesh)
    stats = component_stats(mesh, roots)
    labels = profile["classify"](stats)
    analyze_secs = round(time.time() - t0, 2)
    report["mesh"]["components"] = len(stats)
    report["mesh"]["analysis_seconds"] = analyze_secs
    log("连通分量 %d 个（%.2fs）" % (len(stats), analyze_secs))

    buckets = {name: [] for name in part_names}
    for root, name in labels.items():
        buckets[name].append(root)
    expected = {}
    for name, roots_list in buckets.items():
        tris = sum(stats[r]["tris"] for r in roots_list)
        verts = sum(stats[r]["verts"] for r in roots_list)
        expected[name] = {"components": len(roots_list), "tris": tris, "verts": verts}
        if roots_list:
            lo = [round(min(stats[r]["lo"][k] for r in roots_list), 5) for k in range(3)]
            hi = [round(max(stats[r]["hi"][k] for r in roots_list), 5) for k in range(3)]
            expected[name]["bbox_min"] = lo
            expected[name]["bbox_max"] = hi
        log("  预期 %-10s 分量=%3d tris=%7d verts=%7d"
            % (name, len(roots_list), tris, verts))
    if sum(v["tris"] for v in expected.values()) != in_blender["triangles"]:
        die("部件划分三角面之和不等于总数，分类漏判/重判")
    if sum(v["verts"] for v in expected.values()) != in_blender["vertices"]:
        die("部件划分顶点数之和不等于总数，分类漏判/重判")

    # 4) 打标签并拆分
    build_part_groups(obj, mesh, roots, labels, part_names)
    log("已建顶点组：%s" % ", ".join(part_names))

    t0 = time.time()
    new_objects = [obj]
    for part_name in part_names[1:]:
        t_part = time.time()
        newo = separate_part(obj, part_name)
        newo.name = prefix + part_name
        newo.data.name = prefix + part_name
        new_objects.append(newo)
        log("已分离 %s（%.2fs）" % (newo.name, time.time() - t_part))
    obj.name = prefix + "body"
    obj.data.name = prefix + "body"
    separate_secs = round(time.time() - t0, 2)
    log("拆分完成（%.2fs）" % separate_secs)

    for o in new_objects:
        strip_vertex_groups(o)

    # 5) 应用变换（输入为恒等变换，此处仅为满足"应用全部变换"并留证）
    bpy.ops.object.select_all(action='DESELECT')
    for o in new_objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active = new_objects[0]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    # 5.5) 枢轴原点迁移（第 17 号单）：只动对象原点，世界空间几何零变化
    # 判定口径（为什么不比哈希）：拆分/迁移都不重排顶点，故做**逐顶点索引比对**；
    # 容差 1e-6 m（1 µm）——Blender 顶点坐标以 float32 存储，把局部坐标整体平移后
    # 相对舍入会带来 ~1e-8 m 量级抖动（实测 3.7e-9 m），1 nm 量化哈希会把这种
    # 纯浮点抖动误判成几何变化（第一版就是这么失败的）。另做一次"排序后比对"
    # 作为与顶点顺序无关的旁证，阈值放宽到 1e-5 m（10 µm）。
    import numpy as np
    WORLD_GEOM_TOL_M = 1e-6
    WORLD_GEOM_SORTED_TOL_M = 1e-5
    wp_before = world_positions(new_objects)
    pivot_ok = True
    pivot_part = profile.get("pivot_part")
    if pivot_part:
        t_pivot = time.time()
        target_obj = bpy.data.objects.get(prefix + pivot_part)
        if target_obj is None:
            die("pivot_part=%r 对应对象不存在" % pivot_part)
        target, info = top_face_center(target_obj)
        origin_before, origin_after = move_origin_to(target_obj, target)
        wp_after = world_positions(new_objects)
        per_obj = {}
        max_delta = 0.0
        for name, arr in wp_after.items():
            ref = wp_before[name]
            if arr.shape != ref.shape:
                per_obj[name] = {"shape_before": list(ref.shape),
                                 "shape_after": list(arr.shape),
                                 "index_delta_ok": False}
                pivot_ok = False
                continue
            idx_delta = float(np.abs(arr - ref).max()) if arr.size else 0.0
            ord_a = np.lexsort((arr[:, 2], arr[:, 1], arr[:, 0]))
            ord_b = np.lexsort((ref[:, 2], ref[:, 1], ref[:, 0]))
            sorted_delta = (float(np.abs(arr[ord_a] - ref[ord_b]).max())
                            if arr.size else 0.0)
            idx_ok = idx_delta <= WORLD_GEOM_TOL_M
            # 排序比对只作参考、不参与判定：lexsort 用原始 float64 排序，两点在某轴相差
            # <1e-9 而另轴相差很大时，浮点抖动会让顺序互换，从而把微小抖动放大成假差异。
            per_obj[name] = {
                "vertices": int(arr.shape[0]),
                "max_abs_delta_m": idx_delta,
                "index_delta_ok": idx_ok,
                "sorted_max_abs_delta_m": sorted_delta,
                "origin_after": [round(float(x), 9) for x in
                                 list(bpy.data.objects[name].matrix_world.translation)],
            }
            max_delta = max(max_delta, idx_delta)
            if not idx_ok:
                pivot_ok = False
        pivot_report = {
            "part": pivot_part,
            "object": prefix + pivot_part,
            "origin_before": [round(float(x), 9) for x in origin_before],
            "origin_after": [round(float(x), 9) for x in origin_after],
            "top_face": info,
            "tolerance_m": WORLD_GEOM_TOL_M,
            "sorted_tolerance_m": WORLD_GEOM_SORTED_TOL_M,
            "tolerance_reason": "Blender 顶点坐标为 float32，局部坐标平移后的相对舍入抖动"
                                "实测 3.7e-9 m；1 µm 容差远大于该抖动、远小于任何真实几何变化",
            "world_geometry_max_abs_delta_m": max_delta,
            "objects": per_obj,
            "world_geometry_unchanged": pivot_ok,
            "seconds": round(time.time() - t_pivot, 2),
        }
        report["pivot"] = pivot_report
        log("枢轴：%s 原点 %s → %s（顶面 z_max=%.6f，面积加权，顶点 %d 个，三角形 %d 个，%.2fs）"
            % (pivot_report["object"],
               ["%.6f" % v for v in origin_before], ["%.6f" % v for v in origin_after],
               info["z_max_world"], info["band_vertex_count"], info["triangles_in_band"],
               pivot_report["seconds"]))
        log("枢轴：世界空间几何最大偏差=%.3e m（容差 %.0e m），守恒=%s"
            % (max_delta, WORLD_GEOM_TOL_M, pivot_ok))
        if not pivot_ok:
            die("枢轴迁移改变了世界空间几何（见报告 pivot.objects）")

    # 6) 导出 GLB（贴图原样内嵌；Y-up 保持；不做任何压缩）
    out_dir = os.path.dirname(out_glb)
    if out_dir and not os.path.isdir(out_dir):
        os.makedirs(out_dir, exist_ok=True)
    t0 = time.time()
    bpy.ops.export_scene.gltf(
        filepath=out_glb,
        export_format='GLB',
        export_yup=True,
        export_apply=False,
        use_selection=False,
        use_visible=False,
        export_cameras=False,
        export_lights=False,
        export_animations=False,
        export_skins=False,
        export_morph=False,
        export_extras=False,
        export_texcoords=True,
        export_normals=True,
        export_tangents=False,
        export_materials='EXPORT',
        export_image_format='AUTO',
        export_keep_originals=False,
        export_draco_mesh_compression_enable=False,
        export_shared_accessors=False,
    )
    export_secs = round(time.time() - t0, 2)
    if not os.path.isfile(out_glb):
        die("导出后文件不存在: %s" % out_glb)
    log("导出完成 %s（%.2fs，%.2f MB）"
        % (os.path.basename(out_glb), export_secs, os.path.getsize(out_glb) / 1048576.0))

    # 7) 输出文件级实测 + 对比
    out_summary = glb_summary(out_glb)
    report["output"]["glb"] = out_summary
    report["output"]["export_seconds"] = export_secs
    report["output"]["object_names"] = [o.name for o in
                                       sorted(bpy.context.scene.objects, key=lambda x: x.name)]

    # 各对象实测（Blender 侧）
    objs_sorted = sorted(bpy.context.scene.objects, key=lambda o: o.name)
    actual = {}
    for o in objs_sorted:
        if o.type != "MESH":
            continue
        o.data.calc_loop_triangles()
        actual[o.name] = {
            "verts": len(o.data.vertices),
            "tris": len(o.data.loop_triangles),
            "material_slots": [s.material.name if s.material else None
                               for s in o.material_slots],
            "uv_layers": [uv.name for uv in o.data.uv_layers],
        }
    report["output"]["objects"] = actual

    parts_report = {}
    for name in part_names:
        o = bpy.data.objects.get(prefix + name)
        if o is None:
            die("导出后缺少对象 %s%s" % (prefix, name))
        parts_report[name] = dict(actual[o.name])
        parts_report[name].update({
            "components": expected[name]["components"],
            "expected_tris": expected[name]["tris"],
            "expected_verts": expected[name]["verts"],
            "bbox_min": expected[name].get("bbox_min"),
            "bbox_max": expected[name].get("bbox_max"),
        })
    report["parts"] = parts_report

    sum_verts = sum(v["verts"] for v in actual.values())
    sum_tris = sum(v["tris"] for v in actual.values())

    file_vertex_delta = out_summary["vertices"] - in_summary["vertices"]
    vertex_allowance = int(profile.get("file_vertex_delta_allowance", 0))
    cmp = {
        "input_glb_triangles": in_summary["triangles"],
        "output_glb_triangles": out_summary["triangles"],
        "triangles_equal": in_summary["triangles"] == out_summary["triangles"],
        "input_glb_vertices": in_summary["vertices"],
        "output_glb_vertices": out_summary["vertices"],
        "vertices_equal": in_summary["vertices"] == out_summary["vertices"],
        "file_vertex_delta": file_vertex_delta,
        "file_vertex_delta_allowance": vertex_allowance,
        "vertices_equal_within_allowance": file_vertex_delta == vertex_allowance,
        "file_vertex_delta_reason": profile.get("file_vertex_delta_reason"),
        "input_blender_triangles": in_blender["triangles"],
        "output_blender_triangles_sum": sum_tris,
        "blender_triangles_equal": in_blender["triangles"] == sum_tris,
        "input_blender_vertices": in_blender["vertices"],
        "output_blender_vertices_sum": sum_verts,
        "blender_vertices_equal": in_blender["vertices"] == sum_verts,
        "input_attribute_keys": in_summary["attribute_keys"],
        "output_attribute_keys": out_summary["attribute_keys"],
        "attribute_keys_equal": in_summary["attribute_keys"] == out_summary["attribute_keys"],
        "input_image_sha256": [i["sha256"] for i in in_summary["images"]],
        "output_image_sha256": [i["sha256"] for i in out_summary["images"]],
        # 贴图是否被重编码/重采样：必须按 sha256 集合比，不能按下标比。
        # glTF 导出后 images 数组顺序会变（实测 NormalGL 被排到首位），
        # 按下标比会产出「字节不一致」的假阴性，进而误报「发生重压缩」。
        "images_byte_identical": (
            [i["sha256"] for i in in_summary["images"]]
            == [i["sha256"] for i in out_summary["images"]]),
        "images_byte_identical_as_set": (
            sorted(i["sha256"] for i in in_summary["images"])
            == sorted(i["sha256"] for i in out_summary["images"])),
        "input_nodes": in_summary["nodes"],
        "output_nodes": out_summary["nodes"],
        "input_meshes": in_summary["meshes"],
        "output_meshes": out_summary["meshes"],
    }
    report["comparison"] = cmp
    report["total_seconds"] = round(time.time() - started, 2)

    verdict_ok = (cmp["triangles_equal"] and cmp["vertices_equal_within_allowance"]
                  and cmp["blender_triangles_equal"] and cmp["blender_vertices_equal"]
                  and cmp["images_byte_identical_as_set"] and pivot_ok)
    if not cmp["vertices_equal"] and cmp["vertices_equal_within_allowance"]:
        report["notes"].append(
            "文件级顶点数 %d → %d（差 +%d），已在 profile 允许增量 %d 内：%s"
            % (cmp["input_glb_vertices"], cmp["output_glb_vertices"],
               cmp["file_vertex_delta"], cmp["file_vertex_delta_allowance"],
               cmp.get("file_vertex_delta_reason") or "无说明"))
    if not cmp["attribute_keys_equal"]:
        report["notes"].append(
            "顶点属性集合与输入不一致：%s → %s"
            % (cmp["input_attribute_keys"], cmp["output_attribute_keys"]))
    if not cmp["images_byte_identical_as_set"]:
        report["notes"].append(
            "贴图字节集合与输入不一致（发生重编码/重采样），分辨率未变，见 images 字段")
    elif not cmp["images_byte_identical"]:
        report["notes"].append(
            "贴图字节集合一致（未重压缩、未重采样），仅 GLB 内 images 数组顺序变化，非内容差异")
    for name, info in parts_report.items():
        if info["tris"] != info["expected_tris"]:
            verdict_ok = False
            report["notes"].append("部件 %s 三角面与预期不符" % name)

    report["verdict"] = "PASS" if verdict_ok else "FAIL"
    with open(report_path, "w", encoding="utf-8") as fh:
        json.dump(report, fh, ensure_ascii=False, indent=1)

    log("------------------------------ 验收对比 ------------------------------")
    log("三角面  输入 GLB=%d  输出 GLB=%d  %s"
        % (cmp["input_glb_triangles"], cmp["output_glb_triangles"],
           "相等" if cmp["triangles_equal"] else "不相等"))
    log("顶点数  输入 GLB=%d  输出 GLB=%d  差 +%d（允许 %d）  %s"
        % (cmp["input_glb_vertices"], cmp["output_glb_vertices"],
           cmp["file_vertex_delta"], cmp["file_vertex_delta_allowance"],
           "在允许增量内" if cmp["vertices_equal_within_allowance"] else "超出允许增量"))
    log("三角面  Blender 输入=%d  拆分后合计=%d  %s"
        % (cmp["input_blender_triangles"], cmp["output_blender_triangles_sum"],
           "相等" if cmp["blender_triangles_equal"] else "不相等"))
    log("顶点数  Blender 输入=%d  拆分后合计=%d  %s"
        % (cmp["input_blender_vertices"], cmp["output_blender_vertices_sum"],
           "相等" if cmp["blender_vertices_equal"] else "不相等"))
    for name in part_names:
        info = parts_report[name]
        log("  %-18s verts=%7d tris=%7d 分量=%3d"
            % (prefix + name, info["verts"], info["tris"], info["components"]))
    log("贴图字节集合一致=%s  属性集合一致=%s"
        % (cmp["images_byte_identical_as_set"], cmp["attribute_keys_equal"]))
    log("报告 %s" % report_path)
    log("VERDICT=%s" % report["verdict"])

    if not verdict_ok:
        die("自检未通过，见报告 %s" % report_path)


main()
