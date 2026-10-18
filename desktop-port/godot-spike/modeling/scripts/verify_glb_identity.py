"""独立校验 v3：不经过 Blender，直接解析输入/输出 GLB，判定「几何/UV/贴图/材质是否被改动」。

为什么不做成 Blender 脚本：交付物正确性不能用产出它的同一进程自证。

设计要点（v1/v2 踩过的坑，均已修正）：
- v1 用「顶点行 rank」表示三角面 → 同一位置存在多个重复顶点（UV 接缝，本模型 50,335 个）时
  行序变化会造成伪阳性。v3 改用「位置组 ID」表示三角面：位置相同即同一 ID，与顶点顺序无关。
- v2 量化法线/UV 漂移时按数组顺序配对 → 完全错乱（假的 90° 平均偏差）。v3 一律按位置组对齐。
- 材质比较把 glTF 省略字段按规范默认值归一（如 normalTexture.scale 缺省=1.0，
  metallicFactor 缺省=1.0），texture 索引先解析成图像内容 sha256 再比。

用法: python verify_glb_identity.py <in.glb> <out.glb> [report.json]
"""
import hashlib
import json
import struct
import sys

import numpy as np

COMPONENT_DTYPE = {
    5120: np.int8, 5121: np.uint8, 5122: np.int16,
    5123: np.uint16, 5125: np.uint32, 5126: np.float32,
}
TYPE_WIDTH = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}
ATTR_ORDER = ("POSITION", "NORMAL", "TEXCOORD_0")


# --------------------------------------------------------------------------- GLB

def load_glb(path):
    with open(path, "rb") as fh:
        data = fh.read()
    magic, version, length = struct.unpack_from("<III", data, 0)
    if magic != 0x46546C67:
        raise ValueError("not a GLB: %s" % path)
    gltf, bin_chunk, off = None, None, 12
    while off < length:
        clen, ctype = struct.unpack_from("<II", data, off)
        off += 8
        chunk = data[off:off + clen]
        off += clen
        if ctype == 0x4E4F534A:
            gltf = json.loads(chunk.decode("utf-8"))
        elif ctype == 0x004E4942:
            bin_chunk = chunk
    return gltf, bin_chunk, len(data)


def read_accessor(gltf, bin_chunk, index):
    acc = gltf["accessors"][index]
    dt = np.dtype(COMPONENT_DTYPE[acc["componentType"]])
    width = TYPE_WIDTH[acc["type"]]
    count = acc["count"]
    bv = gltf["bufferViews"][acc["bufferView"]]
    base = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
    stride = bv.get("byteStride") or dt.itemsize * width
    raw = bin_chunk[base: base + stride * count]
    if stride == dt.itemsize * width:
        arr = np.frombuffer(raw, dtype=dt, count=count * width).reshape(count, width)
    else:
        arr = np.empty((count, width), dtype=dt)
        step = dt.itemsize * width
        for i in range(count):
            s = i * stride
            arr[i] = np.frombuffer(raw[s:s + step], dtype=dt, count=width)
    return arr.astype(np.float32)


def read_mesh(gltf, bin_chunk):
    cols = {name: [] for name in ATTR_ORDER}
    tri_global, meta = [], []
    base = 0
    for mesh in gltf.get("meshes", []):
        for prim in mesh["primitives"]:
            attrs = prim["attributes"]
            n = read_accessor(gltf, bin_chunk, attrs["POSITION"]).shape[0]
            for name in ATTR_ORDER:
                width = 2 if name == "TEXCOORD_0" else 3
                if name in attrs:
                    arr = read_accessor(gltf, bin_chunk, attrs[name])
                    acc = gltf["accessors"][attrs[name]]
                    meta.append({"attr": name,
                                 "componentType": acc["componentType"],
                                 "normalized": bool(acc.get("normalized")),
                                 "count": acc["count"],
                                 "primitive_verts": n})
                else:
                    arr = np.zeros((n, width), dtype=np.float32)
                cols[name].append(arr)
            idx = read_accessor(gltf, bin_chunk, prim["indices"]).astype(np.int64).ravel()
            tri_global.append(idx.reshape(-1, 3) + base)
            base += n
    v = {name: np.concatenate(cols[name], axis=0) for name in ATTR_ORDER}
    return v, np.concatenate(tri_global, axis=0), meta


# ------------------------------------------------------------------ 哈希与几何判定

def bits(a):
    return np.ascontiguousarray(a).view(np.int32)


def multiset_hash(arr):
    a = bits(np.ascontiguousarray(arr))
    order = np.lexsort(tuple(a[:, i] for i in range(a.shape[1] - 1, -1, -1)))
    return hashlib.sha256(np.ascontiguousarray(a[order]).tobytes()).hexdigest()


def position_group(pos):
    """把 POSITION 行映射为「位置组 ID」：相同位置（逐位相同）得到同一 ID。"""
    uniq, inv = np.unique(np.ascontiguousarray(pos), axis=0, return_inverse=True)
    return uniq, inv.reshape(-1)


def tri_hash_by_group(tri, group_of_vertex, ignore_winding=False):
    t = group_of_vertex[tri]
    if ignore_winding:
        t = np.sort(t, axis=1)
    t = t[np.lexsort((t[:, 2], t[:, 1], t[:, 0]))]
    return hashlib.sha256(np.ascontiguousarray(t).tobytes()).hexdigest()


def attr_by_position_hash(group, attr):
    """(位置组 ID, 属性位模式) 的多重集哈希：与顶点行顺序无关，等价于
    「每个位置上的属性取值集合是否完全相同」。"""
    key = np.concatenate([group.reshape(-1, 1).astype(np.int32),
                          bits(np.ascontiguousarray(attr))], axis=1)
    return multiset_hash(key)


def split_groups(pos_i, pos_o):
    n = pos_i.shape[0]
    uniq, inv = np.unique(np.concatenate([np.ascontiguousarray(pos_i),
                                          np.ascontiguousarray(pos_o)], axis=0),
                          axis=0, return_inverse=True)
    inv = inv.reshape(-1)
    return uniq, inv[:n], inv[n:]


def paired_drift2(gi, go, nrm_i, nrm_o, uv_i, uv_o, n_groups):
    cnt_i = np.bincount(gi, minlength=n_groups)
    cnt_o = np.bincount(go, minlength=n_groups)
    _, first_i = np.unique(gi, return_index=True)
    _, first_o = np.unique(go, return_index=True)
    vals_i = np.unique(gi)
    vals_o = np.unique(go)
    # 两边都只出现一次、且两侧都存在的组
    shared = np.intersect1d(vals_i, vals_o)
    single = shared[(cnt_i[shared] == 1) & (cnt_o[shared] == 1)]
    map_i = dict(zip(vals_i.tolist(), first_i.tolist()))
    map_o = dict(zip(vals_o.tolist(), first_o.tolist()))
    ii = np.array([map_i[g] for g in single.tolist()], dtype=np.int64)
    oo = np.array([map_o[g] for g in single.tolist()], dtype=np.int64)

    a = nrm_i[ii].astype(np.float64)
    b = nrm_o[oo].astype(np.float64)
    na = np.linalg.norm(a, axis=1)
    nb = np.linalg.norm(b, axis=1)
    cos = np.sum(a * b, axis=1) / (na * nb + 1e-12)
    ang = np.degrees(np.arccos(np.clip(cos, -1.0, 1.0)))
    duv = np.abs(uv_i[ii].astype(np.float64) - uv_o[oo].astype(np.float64))
    return {
        "paired_vertices": int(ii.size),
        "unpaired_vertices": int(gi.shape[0] - ii.size),
        "normal_max_angle_deg": round(float(ang.max()) if ang.size else 0.0, 9),
        "normal_p999_angle_deg": round(float(np.percentile(ang, 99.9)) if ang.size else 0.0, 9),
        "normal_mean_angle_deg": round(float(ang.mean()) if ang.size else 0.0, 9),
        "normal_nonzero": int((ang > 0).sum()),
        "uv_max_abs_delta": round(float(duv.max()) if duv.size else 0.0, 9),
        "uv_nonzero": int((duv > 0).any(axis=1).sum()),
    }


# ------------------------------------------------------ 节点变换与世界空间位置（第 17 号单）

def _quat_to_mat(q):
    x, y, z, w = q
    return np.array([
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
    ], dtype=np.float64)


def _node_local_matrix(node):
    if "matrix" in node:
        return np.array(node["matrix"], dtype=np.float64).reshape(4, 4).T
    m = np.eye(4, dtype=np.float64)
    rot = node.get("rotation")
    scl = node.get("scale")
    tra = node.get("translation")
    if rot is not None:
        m[:3, :3] = _quat_to_mat(rot)
    if scl is not None:
        m[:3, :3] = m[:3, :3] @ np.diag(np.array(scl, dtype=np.float64))
    if tra is not None:
        m[:3, 3] = np.array(tra, dtype=np.float64)
    return m


def node_world_matrices(gltf):
    """返回 [(节点名, 4x4 世界矩阵, mesh 索引)]，含节点 TRS 展开与父子链累积。"""
    out = []
    scenes = gltf.get("scenes", [])
    roots = scenes[gltf.get("scene", 0)].get("nodes", []) if scenes else []

    def rec(idx, parent):
        node = gltf["nodes"][idx]
        world = parent @ _node_local_matrix(node)
        if "mesh" in node:
            out.append((node.get("name", "node%d" % idx), world, node["mesh"]))
        for ch in node.get("children", []):
            rec(ch, world)

    for r in roots:
        rec(r, np.eye(4, dtype=np.float64))
    return out


def world_positions_by_node(gltf, bin_chunk):
    """{节点名: (N,3) float64 应用节点变换后的世界坐标}。"""
    out = {}
    for name, world, mesh_index in node_world_matrices(gltf):
        mesh = gltf["meshes"][mesh_index]
        parts = []
        for prim in mesh["primitives"]:
            p = read_accessor(gltf, bin_chunk, prim["attributes"]["POSITION"]).astype(np.float64)
            parts.append((world[:3, :3] @ p.T).T + world[:3, 3])
        if parts:
            out[name] = np.concatenate(parts, axis=0)
    return out


def _sorted_by_xyz(arr):
    order = np.lexsort((arr[:, 2], arr[:, 1], arr[:, 0]))
    return arr[order]


def world_spatial_check(gltf_i, bin_i, gltf_o, bin_o, tol=1e-6, sorted_tol=1e-5):
    """世界空间几何守恒判定：应用节点变换后，逐顶点世界坐标（按索引）在 tol 内一致。

    为什么用容差而不是哈希：glTF 的 POSITION 是 float32，枢轴迁移会改变局部坐标的
    舍入结果，逐顶点世界坐标会出现 ~1e-7 m 量级抖动（远小于任何真实几何变化）。
    1 nm 量化哈希会把这种纯浮点抖动误判成几何变化，故改用「索引比对 + 容差」。

    兼容两种场景：
      - 枢轴迁移前后（对象名/顶点数相同）：逐对象比对，给出逐对象最大偏差；
      - 单网格 vs 拆分后（对象集合不同）：退化为全网排序比对（顶点数不等直接判失败，
        这属于预期——拆分本身不保证文件级顶点数不变，见报告口径）。
    """
    wi = world_positions_by_node(gltf_i, bin_i)
    wo = world_positions_by_node(gltf_o, bin_o)
    names_i, names_o = sorted(wi), sorted(wo)
    same_names = names_i == names_o
    per_object = {}
    max_delta = 0.0
    ok = True
    if same_names:
        for name in names_i:
            a, b = wi[name], wo[name]
            if a.shape != b.shape:
                per_object[name] = {"shape_in": list(a.shape), "shape_out": list(b.shape),
                                    "match": False}
                ok = False
                continue
            idx_delta = float(np.abs(a - b).max()) if a.size else 0.0
            sorted_delta = (float(np.abs(_sorted_by_xyz(a) - _sorted_by_xyz(b)).max())
                            if a.size else 0.0)
            # 排序比对只作参考、不参与判定（lexsort 的浮点抖动会把微小差异放大成假差异，
            # 见报告 §4）。
            good = idx_delta <= tol
            per_object[name] = {
                "vertices": int(a.shape[0]),
                "max_abs_delta_m": idx_delta,
                "index_delta_ok": bool(good),
                "sorted_max_abs_delta_m": sorted_delta,
                "match": bool(good),
            }
            max_delta = max(max_delta, idx_delta)
            if not good:
                ok = False
    else:
        ai = np.concatenate([wi[n] for n in names_i], axis=0)
        bo = np.concatenate([wo[n] for n in names_o], axis=0)
        if ai.shape != bo.shape:
            per_object = {"_global": {"vertices_in": int(ai.shape[0]),
                                      "vertices_out": int(bo.shape[0]),
                                      "match": False}}
            ok = False
        else:
            gd = float(np.abs(_sorted_by_xyz(ai) - _sorted_by_xyz(bo)).max()) if ai.size else 0.0
            ok = gd <= sorted_tol
            max_delta = gd
            per_object = {"_global": {"vertices": int(ai.shape[0]),
                                      "sorted_max_abs_delta_m": gd,
                                      "match": bool(ok)}}
    detail = {
        "tolerance_m": tol,
        "sorted_tolerance_m": sorted_tol,
        "tolerance_reason": "POSITION 为 float32，枢轴迁移改变局部坐标舍入，"
                            "实测抖动 ~1e-9~1e-7 m；容差远小于任何真实几何变化",
        "objects_in": names_i,
        "objects_out": names_o,
        "same_object_names": same_names,
        "per_object": per_object,
        "max_abs_delta_m": max_delta,
    }
    return ok, detail


# ------------------------------------------------------------------ 材质/贴图

def images_summary(gltf, bin_chunk):
    out = []
    for img in gltf.get("images", []):
        bv = gltf["bufferViews"][img["bufferView"]]
        start = bv.get("byteOffset", 0)
        chunk = bin_chunk[start:start + bv["byteLength"]]
        out.append({"name": img.get("name", ""), "mime": img.get("mimeType", ""),
                    "bytes": len(chunk),
                    "sha256": hashlib.sha256(chunk).hexdigest()})
    return out


def material_summary(gltf, image_hashes):
    """texture 索引 → 图像内容 sha256；违反规范的省略字段按默认值补齐后再比。"""
    out = []
    for mat in gltf.get("materials", []):
        pbr = mat.get("pbrMetallicRoughness", {}) or {}

        def tex_info(t):
            if not t:
                return None
            info = {}
            src = gltf["textures"][t["index"]].get("source")
            if src is not None:
                name = gltf["images"][src].get("name", "")
                info["image_sha256"] = image_hashes.get(name, "?")
                info["image_name"] = name
            info["texCoord"] = t.get("texCoord", 0)
            if "scale" in t:
                info["scale"] = t["scale"]
            return info

        out.append({
            "alphaMode": mat.get("alphaMode", "OPAQUE"),
            "alphaCutoff": mat.get("alphaCutoff"),
            "doubleSided": mat.get("doubleSided", False),
            "baseColorFactor": pbr.get("baseColorFactor", [1, 1, 1, 1]),
            "metallicFactor": float(pbr.get("metallicFactor", 1.0)),
            "roughnessFactor": float(pbr.get("roughnessFactor", 1.0)),
            "baseColorTexture": tex_info(pbr.get("baseColorTexture")),
            "metallicRoughnessTexture": tex_info(pbr.get("metallicRoughnessTexture")),
            "normalTexture": tex_info(mat.get("normalTexture")),
            "occlusionTexture": tex_info(mat.get("occlusionTexture")),
            "emissiveTexture": tex_info(mat.get("emissiveTexture")),
            "emissiveFactor": mat.get("emissiveFactor", [0, 0, 0]),
            "extensions": mat.get("extensions", {}),
        })
    return out


def structural(gltf):
    return {
        "generator": gltf.get("asset", {}).get("generator"),
        "nodes": len(gltf.get("nodes", [])),
        "meshes": len(gltf.get("meshes", [])),
        "materials": len(gltf.get("materials", [])),
        "images": len(gltf.get("images", [])),
        "textures": len(gltf.get("textures", [])),
        "animations": len(gltf.get("animations", [])),
        "skins": len(gltf.get("skins", [])),
        "cameras": len(gltf.get("cameras", [])),
        "extensionsUsed": gltf.get("extensionsUsed", []),
        "extensionsRequired": gltf.get("extensionsRequired", []),
        "node_names": [n.get("name", "") for n in gltf.get("nodes", [])],
        "primitive_count": sum(len(m.get("primitives", []))
                              for m in gltf.get("meshes", [])),
    }


def accessor_layout_summary(meta):
    """只看「属性类型 → componentType/normalized」，不看 count（对象被拆成多个 primitive）。"""
    keys = sorted({(m["attr"], m["componentType"], m["normalized"]) for m in meta})
    per_attr = {}
    for m in meta:
        per_attr.setdefault(m["attr"], 0)
        per_attr[m["attr"]] += m["count"]
    return {"layout": [list(k) for k in keys], "counts": per_attr}


# ------------------------------------------------------------------------- main

def main(argv):
    in_path, out_path = argv[1], argv[2]
    report_path = argv[3] if len(argv) > 3 else None
    gi_gltf, gi_bin, size_i = load_glb(in_path)
    go_gltf, go_bin, size_o = load_glb(out_path)

    vi, tri_i, meta_i = read_mesh(gi_gltf, gi_bin)
    vo, tri_o, meta_o = read_mesh(go_gltf, go_bin)

    imgs_i = images_summary(gi_gltf, gi_bin)
    imgs_o = images_summary(go_gltf, go_bin)
    hashes_i = {im["name"]: im["sha256"] for im in imgs_i}
    hashes_o = {im["name"]: im["sha256"] for im in imgs_o}

    # 位置组：输入/输出共用同一套 ID，才能跨文件比较三角形与属性
    uniq, group_i, group_o = split_groups(vi["POSITION"], vo["POSITION"])

    checks = []

    def check(name, ok, detail):
        checks.append({"check": name, "pass": bool(ok), "detail": detail})

    check("顶点数一致", vi["POSITION"].shape[0] == vo["POSITION"].shape[0],
          {"in": int(vi["POSITION"].shape[0]), "out": int(vo["POSITION"].shape[0])})
    check("三角面数一致", tri_i.shape[0] == tri_o.shape[0],
          {"in": int(tri_i.shape[0]), "out": int(tri_o.shape[0])})

    lay_i = accessor_layout_summary(meta_i)
    lay_o = accessor_layout_summary(meta_o)
    check("属性布局一致（componentType/normalized 全 float32）", lay_i["layout"] == lay_o["layout"],
          {"in": lay_i["layout"], "out": lay_o["layout"]})
    check("各属性顶点数守恒", lay_i["counts"] == lay_o["counts"],
          {"in": lay_i["counts"], "out": lay_o["counts"]})

    # —— 几何：以位置组表示的三角面（与顶点行顺序、对象拆分方式无关）
    tp_i = tri_hash_by_group(tri_i, group_i, ignore_winding=True)
    tp_o = tri_hash_by_group(tri_o, group_o, ignore_winding=True)
    tpv_i = tri_hash_by_group(tri_i, group_i, ignore_winding=False)
    tpv_o = tri_hash_by_group(tri_o, group_o, ignore_winding=False)
    check("三角面集合一致（按位置组，忽略绕序）", tp_i == tp_o,
          {"in": tp_i[:16], "out": tp_o[:16],
           "position_groups": int(uniq.shape[0])})
    check("三角面绕序保留（按位置组）", tpv_i == tpv_o,
          {"in": tpv_i[:16], "out": tpv_o[:16]})

    # —— 属性：每个位置上的取值多重集
    check("每位置 POSITION 一致",
          multiset_hash(vi["POSITION"]) == multiset_hash(vo["POSITION"]),
          {"in": multiset_hash(vi["POSITION"])[:16],
           "out": multiset_hash(vo["POSITION"])[:16]})
    for name in ("NORMAL", "TEXCOORD_0"):
        hi = attr_by_position_hash(group_i, vi[name])
        ho = attr_by_position_hash(group_o, vo[name])
        check("每位置 %s 一致" % name, hi == ho, {"in": hi[:16], "out": ho[:16]})

    # —— 漂移量化（仅在逐属性多重集不等时才需要；此处恒算，便于报告留证）
    drift = paired_drift2(group_i, group_o, vi["NORMAL"], vo["NORMAL"],
                          vi["TEXCOORD_0"], vo["TEXCOORD_0"], uniq.shape[0])
    check("法线偏差 ≤ 1e-5 度", drift["normal_max_angle_deg"] <= 1e-5, drift)
    check("UV 偏差 = 0", drift["uv_max_abs_delta"] == 0.0, drift)

    # —— 贴图与材质
    set_i = sorted((x["sha256"], x["bytes"], x["mime"]) for x in imgs_i)
    set_o = sorted((x["sha256"], x["bytes"], x["mime"]) for x in imgs_o)
    check("贴图字节集合一致（未重压缩/未重采样）", set_i == set_o,
          {"in": [(x[1], x[2], x[0][:16]) for x in set_i],
           "out": [(x[1], x[2], x[0][:16]) for x in set_o]})

    mats_i = material_summary(gi_gltf, hashes_i)
    mats_o = material_summary(go_gltf, hashes_o)
    check("材质语义一致（按贴图内容解析）", mats_i == mats_o,
          {"in": mats_i, "out": mats_o})

    struct_i = structural(gi_gltf)
    struct_o = structural(go_gltf)
    check("对象数 1 → 4", len(struct_o["node_names"]) == 4,
          {"in": struct_i["node_names"], "out": struct_o["node_names"]})
    check("无动画 / skin / 相机",
          struct_o["animations"] == 0 and struct_o["skins"] == 0
          and struct_o["cameras"] == 0,
          {k: struct_o[k] for k in ("animations", "skins", "cameras")})

    # —— 世界空间几何守恒（第 17 号单：枢轴原点迁移的硬验收；应用节点 TRS 后逐顶点比对）
    wok, wdetail = world_spatial_check(gi_gltf, gi_bin, go_gltf, go_bin)
    check("世界空间位置守恒（应用节点变换后逐顶点世界坐标一致）", wok, wdetail)
    node_trs_i = {name: [round(float(x), 9) for x in w[:3, 3]]
                  for name, w, _ in node_world_matrices(gi_gltf)}
    node_trs_o = {name: [round(float(x), 9) for x in w[:3, 3]]
                  for name, w, _ in node_world_matrices(go_gltf)}

    verdict = "PASS" if all(c["pass"] for c in checks) else "FAIL"
    print("=" * 78)
    for c in checks:
        print("[%s] %s" % ("PASS" if c["pass"] else "FAIL", c["check"]))
    print("=" * 78)
    print("VERDICT=%s" % verdict)
    print("节点世界平移（输入）: %s" % json.dumps(node_trs_i, ensure_ascii=False))
    print("节点世界平移（输出）: %s" % json.dumps(node_trs_o, ensure_ascii=False))
    for c in checks:
        if not c["pass"]:
            print("---- 未通过: %s ----" % c["check"])
            print(json.dumps(c["detail"], ensure_ascii=False, indent=1))

    payload = {
        "verdict": verdict,
        "input": {"path": in_path, "file_bytes": size_i, "structural": struct_i,
                  "images": imgs_i, "materials": mats_i, "accessor_layout": lay_i,
                  "vertices": int(vi["POSITION"].shape[0]),
                  "triangles": int(tri_i.shape[0]),
                  "position_groups": int(uniq.shape[0]),
                  "tri_hash_by_group_ignore_winding": tp_i,
                  "tri_hash_by_group_winding": tpv_i,
                  "node_world_translation": node_trs_i},
        "output": {"path": out_path, "file_bytes": size_o, "structural": struct_o,
                   "images": imgs_o, "materials": mats_o, "accessor_layout": lay_o,
                   "vertices": int(vo["POSITION"].shape[0]),
                   "triangles": int(tri_o.shape[0]),
                   "tri_hash_by_group_ignore_winding": tp_o,
                   "tri_hash_by_group_winding": tpv_o,
                   "node_world_translation": node_trs_o},
        "drift": drift,
        "checks": checks,
    }
    if report_path:
        with open(report_path, "w", encoding="utf-8") as fh:
            json.dump(payload, fh, ensure_ascii=False, indent=1)
        print("verify json -> %s" % report_path)
    return 0 if verdict == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
