## split_cars.py — Generic passenger car pack（Sketchfab CC-BY）显式分组拆车（2026-10-23 v4 终版）
## 用法：blender -b --python split_cars.py -- <pack_dir> <out_dir>
## 包结构（逐网格质心 dump 实证）：3 列阵停放 10 台整车 + 地面圆盘 Cylinder001；
## Blender 导入时重名轮组被加 .001 后缀。车身与轮组的归属按 dump 硬编码（一次性包结构）。
## 每车 = 车身组 + 4 轮组 join 单网格 → prop_car_<key>.glb + 工作台缩略图 PNG。
## v1 按 Body 组（漏轮/多变体）→ v2 最近车身（错配）→ v3 角度/并查集聚类（被地面盘桥接）→ v4 显式映射。
import bpy
import os
import sys
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
pack_dir, out_dir = argv[0], argv[1]

CARS = {
    "sedan": ["Sedan Body", "Wheel_A", "Wheel_A001", "Wheel_A002", "Wheel_A003"],
    "hatchback": ["Hatchback Body", "Wheel_B", "Wheel_B001", "Wheel_B002", "Wheel_B003"],
    "compact": ["Compact Body", "Wheel_C", "Wheel_C001", "Wheel_C002", "Wheel_C003"],
    "minivan": ["minivan body", "Wheel_D", "Wheel_D001", "Wheel_D002", "Wheel_D003"],
    "pickup": ["Pickup Body", "Wheel_E", "Wheel_E001", "Wheel_E002", "Wheel_E003"],
    "coupe": ["Coupe Body", "Wheel_F", "Wheel_F001", "Wheel_F002", "Wheel_F003"],
    "offroad": ["Offroad Body", "Wheel_G", "Wheel_G001", "Wheel_G001.001", "Wheel_G002"],
    "sport": ["Sport body", "Wheel_H", "Wheel_H001", "Wheel_H002", "Wheel_H003"],
    "wagon": ["Wagon Body", "Wheel_A.001", "Wheel_A001.001", "Wheel_A002.001", "Wheel_A003.001"],
    "suv": ["SUV Body", "Wheel_E.001", "Wheel_E001.001", "Wheel_E002.001", "Wheel_E003.001"],
}


def children_meshes(root):
    out = []
    stack = list(root.children) if root else []
    while stack:
        o = stack.pop()
        if o.type == "MESH":
            out.append(o)
        stack.extend(o.children)
    return out


for key, group_names in CARS.items():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(pack_dir, "scene.gltf"))
    keep = []
    missing = []
    for gname in group_names:
        g = bpy.data.objects.get(gname)
        if g is None:
            missing.append(gname)
            continue
        keep.extend(children_meshes(g))
    if missing:
        print("SPLIT %s MISSING groups: %s" % (key, missing))
    bpy.ops.object.select_all(action="DESELECT")
    for o in keep:
        o.select_set(True)
    if not keep:
        print("SPLIT %s nothing to export" % key)
        continue
    bpy.context.view_layer.objects.active = keep[0]
    bpy.ops.object.join()
    joined = bpy.context.view_layer.objects.active
    joined.name = "car_%s" % key
    out = os.path.join(out_dir, "prop_car_%s.glb" % key)
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True)
    d = joined.dimensions
    print("SPLIT %s dims=%.2f x %.2f x %.2f meshes=%d" % (key, d.x, d.y, d.z, len(keep)))
    # 缩略图（工作台 3/4 俯视）
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.render.resolution_x = 640
    scene.render.resolution_y = 480
    pts = [joined.matrix_world @ Vector(v) for v in joined.bound_box]
    cx = sum(p.x for p in pts) / len(pts)
    cy = sum(p.y for p in pts) / len(pts)
    cz = sum(p.z for p in pts) / len(pts)
    cam = bpy.data.objects.get("Cam")
    if cam is None:
        cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
        scene.collection.objects.link(cam)
    cam.location = Vector((cx + 7, cy + 5.5, cz + 7))
    cam.rotation_euler = (Vector((cx, cy, cz)) - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    scene.render.filepath = os.path.join(out_dir, "prop_car_%s.png" % key)
    bpy.ops.render.render(write_still=True)
