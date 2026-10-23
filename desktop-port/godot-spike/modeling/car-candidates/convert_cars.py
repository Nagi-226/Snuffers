## convert_cars.py — KayKit City Builder Bits gltf → GLB 单文件烘焙（2026-10-23）
## 用法：blender -b --python convert_cars.py -- <src_dir> <out_dir>
## src_dir 内含 car_*.gltf + car_*.bin + citybits_texture.png（KayKit CC0 原始文件，不入库）
## 输出 prop_car_*.glb（入 godot/assets/models/）
import bpy
import os
import sys

argv = sys.argv[sys.argv.index("--") + 1:]
src_dir, out_dir = argv[0], argv[1]

CARS = ["sedan", "hatchback", "stationwagon", "taxi", "police"]

for car in CARS:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    src = os.path.join(src_dir, "car_%s.gltf" % car)
    bpy.ops.import_scene.gltf(filepath=src)
    out = os.path.join(out_dir, "prop_car_%s.glb" % car)
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB")
    # 尺寸读数：车长/宽/高供碰撞盒定参
    dims = [o.dimensions for o in bpy.data.objects if o.type == "MESH"]
    if dims:
        dx = max(d.x for d in dims)
        dy = max(d.y for d in dims)
        dz = max(d.z for d in dims)
        print("CAR %s dims (blender xyz) = %.2f x %.2f x %.2f" % (car, dx, dy, dz))
    print("CAR %s exported -> %s" % (car, out))
