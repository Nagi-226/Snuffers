# verify_em57p_visual.py — 两件事（分析用，非交付）：
#   1) 对照组：em57p.glb 导入后【不做任何拆分】直接导出，量顶点数变化 → 证明 +39 来自导出器而非拆分
#   2) 从 em57p_viewmodel.glb 出交付级渲染：整枪两视角 + 每个部件隔离两视角（按对象拆，不用材质猜测）
# 用法: blender.exe -b --factory-startup --python-exit-code 1 --python verify_em57p_visual.py -- <原始.glb> <拆分后.glb> <渲染输出目录> <对照导出.glb>
import json
import os
import struct
import sys

import bpy
from mathutils import Vector

GLB_MAGIC = 0x46546C67
CHUNK_JSON = 0x4E4F534A


def glb_counts(path):
    """只读 GLB JSON：返回 (vertices, triangles, nodes, meshes, primitives)。"""
    with open(path, "rb") as fh:
        blob = fh.read()
    magic, _ver, total = struct.unpack_from("<III", blob, 0)
    if magic != GLB_MAGIC:
        raise SystemExit("不是 GLB: %s" % path)
    offset, js = 12, None
    while offset + 8 <= total:
        clen, ctype = struct.unpack_from("<II", blob, offset)
        offset += 8
        data = blob[offset:offset + clen]
        offset += clen
        if ctype == CHUNK_JSON:
            js = json.loads(data.decode("utf-8"))
    acc = js.get("accessors") or []
    verts = tris = prims = 0
    for mesh in js.get("meshes") or []:
        for prim in mesh.get("primitives") or []:
            prims += 1
            attrs = prim.get("attributes") or {}
            if "POSITION" in attrs:
                verts += int(acc[attrs["POSITION"]].get("count", 0))
            if "indices" in prim:
                tris += int(acc[prim["indices"]].get("count", 0)) // 3
    return {"vertices": verts, "triangles": tris, "nodes": len(js.get("nodes") or []),
            "meshes": len(js.get("meshes") or []), "primitives": prims,
            "file_bytes": len(blob)}


def export_glb(path):
    bpy.ops.export_scene.gltf(
        filepath=path, export_format='GLB', export_yup=True, export_apply=False,
        use_selection=False, use_visible=False, export_cameras=False, export_lights=False,
        export_animations=False, export_skins=False, export_morph=False, export_extras=False,
        export_texcoords=True, export_normals=True, export_tangents=False,
        export_materials='EXPORT', export_image_format='AUTO', export_keep_originals=False,
        export_draco_mesh_compression_enable=False, export_shared_accessors=False)


def parse_args():
    argv = sys.argv
    argv = argv[argv.index("--") + 1:] if "--" in argv else []
    if len(argv) < 4:
        raise SystemExit("ERR 需要 <原始.glb> <拆分后.glb> <渲染目录> <对照导出.glb>")
    return [os.path.abspath(a) for a in argv[:4]]


def make_camera(scene, ortho):
    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = ortho
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    return cam, cam_data


def look_at(cam, target, direction):
    d = Vector(direction).normalized()
    cam.location = Vector(target) + d * 3.0
    cam.rotation_euler = (Vector(target) - cam.location).to_track_quat("-Z", "Y").to_euler()


def main():
    src, viewmodel, outdir, control_out = parse_args()
    os.makedirs(outdir, exist_ok=True)

    # ---------- 1) 对照组 ----------
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=src)
    objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    print("CTRL: 导入对象数=%d verts=%d" % (len(objs), len(objs[0].data.vertices)), flush=True)
    export_glb(control_out)
    c_src, c_out = glb_counts(src), glb_counts(control_out)
    print("CTRL: 原始 GLB      %r" % (c_src,), flush=True)
    print("CTRL: 未拆分往返 GLB %r" % (c_out,), flush=True)
    print("CTRL: 顶点差=%d 三角面差=%d（若顶点差=+39 则与拆分无关，纯导出器行为）"
          % (c_out["vertices"] - c_src["vertices"],
             c_out["triangles"] - c_src["triangles"]), flush=True)

    # ---------- 2) 交付级渲染 ----------
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=viewmodel)
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    print("REN: 拆分后对象 = %s" % sorted(o.name for o in meshes), flush=True)

    scene = bpy.context.scene
    world = bpy.data.worlds.new("w")
    world.use_nodes = False
    world.color = (1.0, 1.0, 1.0)
    scene.world = world
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.render.resolution_x = 1400
    scene.render.resolution_y = 900
    scene.view_settings.view_transform = "Standard"
    shading = scene.display.shading
    shading.show_object_outline = False

    lo = Vector((1e9,) * 3)
    hi = Vector((-1e9,) * 3)
    for o in meshes:
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            for k in range(3):
                lo[k] = min(lo[k], w[k])
                hi[k] = max(hi[k], w[k])
    centre = (lo + hi) * 0.5
    size = max(hi - lo)
    cam, cam_data = make_camera(scene, size * 1.15)

    # 整枪：贴图模式
    shading.light = "STUDIO"
    shading.color_type = "TEXTURE"
    shading.show_cavity = True
    shading.cavity_type = "BOTH"
    for tag, d in (("side", (1.0, -0.05, 0.05)), ("three_quarter", (1.0, 0.9, 0.55))):
        look_at(cam, centre, d)
        cam_data.ortho_scale = size * 1.15
        scene.render.filepath = os.path.join(outdir, "whole_%s.png" % tag)
        bpy.ops.render.render(write_still=True)
        print("REN: whole_%s ok" % tag, flush=True)

    # 部件隔离：不透明纯色，其余纯白（与白底同色=隐形）
    shading.light = "FLAT"
    shading.color_type = "MATERIAL"
    shading.show_cavity = False
    palette = {"magazine": (0.92, 0.10, 0.10, 1.0), "optic": (0.10, 0.70, 0.20, 1.0),
               "laser_module": (0.10, 0.35, 0.92, 1.0)}
    white = bpy.data.materials.new(name="invisible_white")
    white.diffuse_color = (1.0, 1.0, 1.0, 1.0)
    for o in meshes:
        o.data.materials.clear()
        o.data.materials.append(white)
    parts = [o for o in meshes if not o.name.endswith("_body")]
    for o in parts:
        part = o.name.split("_", 1)[1]
        mat = bpy.data.materials.new(name="hl_%s" % part)
        mat.diffuse_color = palette.get(part, (0.9, 0.5, 0.1, 1.0))
        o.data.materials.clear()
        o.data.materials.append(mat)
        plo, phi = Vector((1e9,) * 3), Vector((-1e9,) * 3)
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            for k in range(3):
                plo[k] = min(plo[k], w[k])
                phi[k] = max(phi[k], w[k])
        pc = (plo + phi) * 0.5
        psize = max(phi - plo)
        for tag, d in (("side", (1.0, -0.10, 0.10)), ("34", (1.0, 0.75, 0.55))):
            look_at(cam, pc, d)
            cam_data.ortho_scale = max(psize * 1.35, 0.06)
            scene.render.filepath = os.path.join(outdir, "part_%s_%s.png" % (part, tag))
            bpy.ops.render.render(write_still=True)
            print("REN: part_%s_%s ok" % (part, tag), flush=True)
        o.data.materials.clear()
        o.data.materials.append(white)

    # 拆走三个部件后的机体（检查有没有被"偷走"可见蒙皮）
    for o in meshes:
        o.hide_render = not o.name.endswith("_body")
    for tag, d in (("side", (1.0, -0.05, 0.05)), ("grip34", (0.9, -0.75, -0.85))):
        body = [o for o in meshes if o.name.endswith("_body")][0]
        blo, bhi = Vector((1e9,) * 3), Vector((-1e9,) * 3)
        for c in body.bound_box:
            w = body.matrix_world @ Vector(c)
            for k in range(3):
                blo[k] = min(blo[k], w[k])
                bhi[k] = max(bhi[k], w[k])
        look_at(cam, (blo + bhi) * 0.5, d)
        cam_data.ortho_scale = max(bhi - blo) * 1.15
        body.data.materials[0].diffuse_color = (0.78, 0.78, 0.78, 1.0)
        scene.render.filepath = os.path.join(outdir, "body_rest_%s.png" % tag)
        bpy.ops.render.render(write_still=True)
        print("REN: body_rest_%s ok" % tag, flush=True)
    print("REN: DONE", flush=True)


main()
