"""weapon_postprocess.py — EM-68A 武器 GLB 后处理：原样保管 + 结构化拆分。

## 为什么这样做（设计约束，来自 W9 派单 2026-10-18）
机主已把 AI 图生 3D 产物验收为"完美成品"，因此本脚本**不做任何资产优化**：
- 不做减面/重拓扑/顶点合并/法线重算
- 不重压缩、不重采样贴图
- 只做一件事：把"弹匣 / 瞄具 / 下挂榴弹模块"从单一网格里按连通分量分离成独立子对象，
  以便换弹、换镜、挂件等动画/挂点需求；其余几何全部留在机体对象里。

拆分只允许"分组/分离已有几何"：分离按连通分量整块搬移，不增删改任何顶点与 UV。

## 用法
    blender.exe -b --python weapon_postprocess.py -- em68a.glb [输出.glb] [报告.json]
默认输出：与输入同目录的 em68a_viewmodel.glb + weapon_postprocess_report.json

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

# 部件归属规则（实测自 em68a.glb，坐标单位 = 米，朝向：枪口 +Y、枪托 -Y、上 +Z）
MAG_MIN_Z = -0.05          # 弹匣：整体位于机匣下方
MAG_CENTER_Y = (-0.10, 0.13)
OPTIC_MIN_Z = 0.125        # 瞄具：整体位于顶部导轨之上（导轨顶面实测 0.1328）
OPTIC_CENTER_Y = (-0.05, 0.10)   # 仅红点镜，排除前后机械照门（属机体的固定件）
GL_MIN_CENTER_Y = 0.10     # 下挂榴弹模块：位于前段
GL_MAX_Z = 0.04            # 且整体低于枪膛高度

PART_NAMES = ("body", "magazine", "optic", "gl_module")
OBJECT_PREFIX = "em68a_"
GLB_MAGIC = 0x46546C67
CHUNK_JSON = 0x4E4F534A
CHUNK_BIN = 0x004E4942


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


def classify(stats):
    """按包围盒空间关系把连通分量归入 4 个部件。规则见文件头常量。"""
    labels = {}
    for root, st in stats.items():
        lo, hi = st["lo"], st["hi"]
        cy = (lo[1] + hi[1]) * 0.5
        if lo[2] > OPTIC_MIN_Z and OPTIC_CENTER_Y[0] < cy < OPTIC_CENTER_Y[1]:
            labels[root] = "optic"
        elif hi[2] < MAG_MIN_Z and MAG_CENTER_Y[0] < cy < MAG_CENTER_Y[1]:
            labels[root] = "magazine"
        elif cy > GL_MIN_CENTER_Y and hi[2] < GL_MAX_Z:
            labels[root] = "gl_module"
        else:
            labels[root] = "body"
    return labels


# ---------------------------------------------------------------- 拆分

def build_part_groups(obj, mesh, roots, labels):
    """用顶点组承载部件归属，供后续分多次 separate 时保持标签不丢。"""
    for name in PART_NAMES:
        obj.vertex_groups.new(name=name)
    buckets = {name: [] for name in PART_NAMES}
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

def main():
    started = time.time()
    argv = sys.argv
    argv = argv[argv.index("--") + 1:] if "--" in argv else []
    if not argv:
        die("用法: blender.exe -b --python weapon_postprocess.py -- <in.glb> [out.glb] [report.json]")
    src = os.path.abspath(argv[0])
    if not os.path.isfile(src):
        die("输入不存在: %s" % src)
    out_glb = os.path.abspath(argv[1]) if len(argv) > 1 else os.path.join(
        os.path.dirname(src), "em68a_viewmodel.glb")
    report_path = os.path.abspath(argv[2]) if len(argv) > 2 else os.path.join(
        os.path.dirname(src), "weapon_postprocess_report.json")
    log("输入 %s" % src)
    log("输出 %s" % out_glb)

    report = {
        "script": "weapon_postprocess.py",
        "blender_version": bpy.app.version_string,
        "input": {}, "output": {}, "mesh": {}, "parts": {},
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
    labels = classify(stats)
    analyze_secs = round(time.time() - t0, 2)
    report["mesh"]["components"] = len(stats)
    report["mesh"]["analysis_seconds"] = analyze_secs
    log("连通分量 %d 个（%.2fs）" % (len(stats), analyze_secs))

    buckets = {name: [] for name in PART_NAMES}
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
    build_part_groups(obj, mesh, roots, labels)
    log("已建顶点组：%s" % ", ".join(PART_NAMES))

    t0 = time.time()
    new_objects = [obj]
    for part_name in ("magazine", "optic", "gl_module"):
        t_part = time.time()
        newo = separate_part(obj, part_name)
        newo.name = OBJECT_PREFIX + part_name
        newo.data.name = OBJECT_PREFIX + part_name
        new_objects.append(newo)
        log("已分离 %s（%.2fs）" % (newo.name, time.time() - t_part))
    obj.name = OBJECT_PREFIX + "body"
    obj.data.name = OBJECT_PREFIX + "body"
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
    for name in PART_NAMES:
        o = bpy.data.objects.get(OBJECT_PREFIX + name)
        if o is None:
            die("导出后缺少对象 %s%s" % (OBJECT_PREFIX, name))
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

    cmp = {
        "input_glb_triangles": in_summary["triangles"],
        "output_glb_triangles": out_summary["triangles"],
        "triangles_equal": in_summary["triangles"] == out_summary["triangles"],
        "input_glb_vertices": in_summary["vertices"],
        "output_glb_vertices": out_summary["vertices"],
        "vertices_equal": in_summary["vertices"] == out_summary["vertices"],
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

    verdict_ok = (cmp["triangles_equal"] and cmp["vertices_equal"]
                  and cmp["blender_triangles_equal"] and cmp["blender_vertices_equal"]
                  and cmp["images_byte_identical_as_set"])
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
    log("顶点数  输入 GLB=%d  输出 GLB=%d  %s"
        % (cmp["input_glb_vertices"], cmp["output_glb_vertices"],
           "相等" if cmp["vertices_equal"] else "不相等"))
    log("三角面  Blender 输入=%d  拆分后合计=%d  %s"
        % (cmp["input_blender_triangles"], cmp["output_blender_triangles_sum"],
           "相等" if cmp["blender_triangles_equal"] else "不相等"))
    log("顶点数  Blender 输入=%d  拆分后合计=%d  %s"
        % (cmp["input_blender_vertices"], cmp["output_blender_vertices_sum"],
           "相等" if cmp["blender_vertices_equal"] else "不相等"))
    for name in PART_NAMES:
        info = parts_report[name]
        log("  %-18s verts=%7d tris=%7d 分量=%3d"
            % (OBJECT_PREFIX + name, info["verts"], info["tris"], info["components"]))
    log("贴图字节集合一致=%s  属性集合一致=%s"
        % (cmp["images_byte_identical_as_set"], cmp["attribute_keys_equal"]))
    log("报告 %s" % report_path)
    log("VERDICT=%s" % report["verdict"])

    if not verdict_ok:
        die("自检未通过，见报告 %s" % report_path)


main()
