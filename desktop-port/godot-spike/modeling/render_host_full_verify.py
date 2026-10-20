"""渲染 host_parasite_full.glb 三视图验证图（补全下半身验收用）。"""
import bpy, sys, math
import mathutils

argv = sys.argv[sys.argv.index("--") + 1:]
src, dst_prefix = argv[0], argv[1]

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)

# 全场景包围盒
mins = mathutils.Vector((1e9, 1e9, 1e9))
maxs = mathutils.Vector((-1e9, -1e9, -1e9))
for obj in bpy.data.objects:
    if obj.type != "MESH":
        continue
    for corner in obj.bound_box:
        w = obj.matrix_world @ mathutils.Vector(corner)
        mins = mathutils.Vector(map(min, mins, w))
        maxs = mathutils.Vector(map(max, maxs, w))
center = (mins + maxs) / 2
size = (maxs - mins).length

scene = bpy.context.scene
scene.render.engine = "BLENDER_WORKBENCH"
scene.display.shading.light = "STUDIO"
scene.display.shading.color_type = "TEXTURE"
scene.render.resolution_x = 640
scene.render.resolution_y = 640
scene.world = bpy.data.worlds.new("W")
scene.world.color = (0.85, 0.85, 0.85)

cam_data = bpy.data.cameras.new("Cam")
cam = bpy.data.objects.new("Cam", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam
cam_data.clip_start = 0.01

dist = size * 1.1
for tag, direction in [("front", mathutils.Vector((0, -1, 0.15))),
                       ("side", mathutils.Vector((1, 0, 0.15))),
                       ("back", mathutils.Vector((0, 1, 0.15)))]:
    d = direction.normalized()
    cam.location = center + d * dist
    look = (center - cam.location).normalized()
    cam.rotation_euler = look.to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = "%s_%s.png" % (dst_prefix, tag)
    bpy.ops.render.render(write_still=True)

print("VERIFY bbox_min=%s bbox_max=%s" % (tuple(round(v, 3) for v in mins), tuple(round(v, 3) for v in maxs)))
