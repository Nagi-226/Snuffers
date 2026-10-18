# probe_glb_parts.py — 通用 GLB 体检探针（分析用，非交付）
# 用法: blender.exe -b --factory-startup --python-exit-code 1 --python probe_glb_parts.py -- <in.glb> <out.json>
# 产出: 文件级结构（节点/网格/图元/材质/贴图）+ Blender 侧几何与连通分量统计（按三角面降序）
import hashlib
import json
import os
import struct
import sys

import bpy
from mathutils import Vector

MAGIC = 0x46546C67
CHUNK_JSON = 0x4E4F534A
CHUNK_BIN = 0x004E4942


def log(msg):
    print("PROBE: %s" % msg, flush=True)


def parse_args():
    argv = sys.argv
    argv = argv[argv.index("--") + 1:] if "--" in argv else []
    if len(argv) < 2:
        raise SystemExit("PROBE_ERR 需要 <in.glb> <out.json>")
    return os.path.abspath(argv[0]), os.path.abspath(argv[1])


def sha256_bytes(data):
    return hashlib.sha256(data).hexdigest()


def read_glb(path):
    with open(path, "rb") as fh:
        blob = fh.read()
    magic, version, total = struct.unpack_from("<III", blob, 0)
    if magic != MAGIC:
        raise SystemExit("PROBE_ERR 不是 GLB: magic=%08x" % magic)
    off = 12
    gltf, binchunk = None, b""
    while off < total:
        clen, ctype = struct.unpack_from("<II", blob, off)
        body = blob[off + 8:off + 8 + clen]
        if ctype == CHUNK_JSON:
            gltf = json.loads(body.decode("utf-8"))
        elif ctype == CHUNK_BIN:
            binchunk = body
        off += 8 + clen + ((4 - clen % 4) % 4 if clen % 4 else 0)
    if gltf is None:
        raise SystemExit("PROBE_ERR 缺少 JSON chunk")
    return gltf, binchunk, len(blob), version


def image_bytes(gltf, binchunk, idx):
    img = gltf.get("images", [])[idx]
    if "bufferView" in img:
        bv = gltf["bufferViews"][img["bufferView"]]
        start = bv.get("byteOffset", 0)
        return binchunk[start:start + bv["byteLength"]]
    uri = img.get("uri", "")
    if uri.startswith("data:"):
        import base64
        return base64.b64decode(uri.split(",", 1)[1])
    raise SystemExit("PROBE_ERR image %d 无内嵌数据" % idx)


def glb_summary(path):
    gltf, binchunk, file_bytes, version = read_glb(path)
    prims = []
    for mesh in gltf.get("meshes", []):
        for prim in mesh.get("primitives", []):
            attrs = prim.get("attributes", {})
            acc = {k: gltf["accessors"][v]["count"] for k, v in attrs.items()}
            tri_acc = gltf["accessors"][prim["indices"]]["count"] if "indices" in prim else 0
            prims.append({
                "attributes": sorted(attrs.keys()),
                "attr_counts": acc,
                "index_count": tri_acc,
                "triangles": tri_acc // 3,
                "material": prim.get("material"),
            })
    mats = []
    for m in gltf.get("materials", []):
        pbr = m.get("pbrMetallicRoughness", {})
        mats.append({
            "name": m.get("name"),
            "alphaMode": m.get("alphaMode"),
            "doubleSided": m.get("doubleSided"),
            "baseColorTexture": "baseColorTexture" in pbr,
            "metallicRoughnessTexture": "metallicRoughnessTexture" in pbr,
            "normalTexture": "normalTexture" in m,
            "normalTextureScale": (m.get("normalTexture") or {}).get("scale", 1),
            "occlusionTexture": "occlusionTexture" in m,
            "emissiveTexture": "emissiveTexture" in m,
            "metallicFactor": pbr.get("metallicFactor", 1),
            "roughnessFactor": pbr.get("roughnessFactor", 1),
            "baseColorFactor": pbr.get("baseColorFactor", [1, 1, 1, 1]),
            "extensions": sorted((m.get("extensions") or {}).keys()),
        })
    images = []
    for i, img in enumerate(gltf.get("images", [])):
        data = image_bytes(gltf, binchunk, i)
        images.append({"mime": img.get("mimeType"), "byte_length": len(data),
                       "sha256": sha256_bytes(data)})
    nodes = [{"name": n.get("name"), "mesh": n.get("mesh"),
              "has_matrix": "matrix" in n,
              "trs": {k: n[k] for k in ("translation", "rotation", "scale") if k in n}}
             for n in gltf.get("nodes", [])]
    return {
        "file_bytes": file_bytes,
        "glb_version": version,
        "generator": gltf.get("asset", {}).get("generator"),
        "counts": {
            "nodes": len(gltf.get("nodes", [])),
            "meshes": len(gltf.get("meshes", [])),
            "primitives": len(prims),
            "materials": len(mats),
            "images": len(images),
            "textures": len(gltf.get("textures", [])),
            "animations": len(gltf.get("animations", [])),
            "skins": len(gltf.get("skins", [])),
            "cameras": len(gltf.get("cameras", [])),
        },
        "extensions_used": gltf.get("extensionsUsed", []),
        "nodes": nodes,
        "primitives": prims,
        "materials": mats,
        "images": images,
    }


def component_stats(me):
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

    stats = {}
    for poly in me.polygons:
        r = find(poly.vertices[0])
        st = stats.setdefault(r, {"tris": 0, "verts": set(),
                                  "lo": [1e9, 1e9, 1e9], "hi": [-1e9, -1e9, -1e9]})
        st["tris"] += len(poly.vertices) - 2
        for vi in poly.vertices:
            st["verts"].add(vi)
            v = me.vertices[vi].co
            for k in range(3):
                st["lo"][k] = min(st["lo"][k], v[k])
                st["hi"][k] = max(st["hi"][k], v[k])
    out = []
    for root, st in stats.items():
        lo, hi = st["lo"], st["hi"]
        out.append({
            "root": root,
            "tris": st["tris"],
            "verts": len(st["verts"]),
            "bbox_min": [round(x, 5) for x in lo],
            "bbox_max": [round(x, 5) for x in hi],
            "center": [round((lo[i] + hi[i]) * 0.5, 5) for i in range(3)],
            "size": [round(hi[i] - lo[i], 5) for i in range(3)],
        })
    out.sort(key=lambda d: d["tris"], reverse=True)
    return out


def blender_summary(src):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=src)
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    log("导入完成，MESH 对象 %d 个" % len(meshes))
    info = {"objects": [], "images": []}
    total_tris = total_verts = 0
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for obj in meshes:
        me = obj.data
        tris = sum(len(p.vertices) - 2 for p in me.polygons)
        total_tris += tris
        total_verts += len(me.vertices)
        for c in obj.bound_box:
            w = obj.matrix_world @ Vector(c)
            for i in range(3):
                lo[i] = min(lo[i], w[i])
                hi[i] = max(hi[i], w[i])
        comps = component_stats(me)
        info["objects"].append({
            "name": obj.name,
            "mesh_name": me.name,
            "verts": len(me.vertices),
            "tris": tris,
            "polys": len(me.polygons),
            "all_tri_polys": all(len(p.vertices) == 3 for p in me.polygons),
            "all_smooth": all(p.use_smooth for p in me.polygons),
            "uv_layers": [u.name for u in me.uv_layers],
            "materials": [m.name if m else None for m in me.materials],
            "transform": {
                "location": [round(v, 6) for v in obj.location],
                "rotation_euler": [round(v, 6) for v in obj.rotation_euler],
                "scale": [round(v, 6) for v in obj.scale],
                "matrix_world_is_identity": obj.matrix_world == obj.matrix_world.Identity(4),
            },
            "component_count": len(comps),
            "components": comps,
        })
    for img in bpy.data.images:
        if img.source == "FILE" or img.packed_file:
            info["images"].append({"name": img.name, "size": list(img.size),
                                   "colorspace": img.colorspace_settings.name})
    info["total_tris"] = total_tris
    info["total_verts"] = total_verts
    info["scene_bbox_min"] = [round(v, 5) for v in lo]
    info["scene_bbox_max"] = [round(v, 5) for v in hi]
    return info


def main():
    src, out = parse_args()
    log("文件级解析 %s" % os.path.basename(src))
    summary = {"input": glb_summary(src)}
    log("文件级: %s" % json.dumps(summary["input"]["counts"], ensure_ascii=False))
    summary["blender"] = blender_summary(src)
    os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
    with open(out, "w", encoding="utf-8") as fh:
        json.dump(summary, fh, ensure_ascii=False, indent=1)
    log("写出 %s" % out)
    log("三角面 %d / 顶点 %d / 分量 %d" % (
        summary["blender"]["total_tris"], summary["blender"]["total_verts"],
        summary["blender"]["objects"][0]["component_count"] if summary["blender"]["objects"] else 0))


main()
