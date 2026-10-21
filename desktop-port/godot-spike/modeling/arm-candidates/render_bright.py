import bpy, sys, math, os
from mathutils import Vector

argv = sys.argv[sys.argv.index("--")+1:]
glb, out_prefix, cam_loc, cam_look = argv[0], argv[1], eval(argv[2]), eval(argv[3])
if not os.path.isabs(out_prefix):
    out_prefix = os.path.join(os.path.dirname(os.path.abspath(__file__)), out_prefix)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb)

sc = bpy.context.scene
try:
    sc.render.engine = 'BLENDER_EEVEE'
except TypeError:
    sc.render.engine = 'BLENDER_EEVEE_NEXT'
sc.render.resolution_x = 1000
sc.render.resolution_y = 640
sc.world = bpy.data.worlds.new("w")
sc.world.use_nodes = True
sc.world.node_tree.nodes["Background"].inputs[0].default_value = (0.3, 0.3, 0.32, 1)
for i, rot in enumerate([(math.radians(60), math.radians(10), math.radians(30)),
                          (math.radians(50), 0, math.radians(-120)),
                          (math.radians(-50), 0, math.radians(160))]):
    ld = bpy.data.lights.new("k%d" % i, 'SUN')
    ld.energy = 4.0
    lo = bpy.data.objects.new("k%d" % i, ld)
    lo.rotation_euler = rot
    sc.collection.objects.link(lo)

cam_data = bpy.data.cameras.new("cam")
cam = bpy.data.objects.new("cam", cam_data)
sc.collection.objects.link(cam)
sc.camera = cam

views = {
    "fp": (Vector(cam_loc), Vector(cam_look), None),
    "side": (Vector((1.2, -0.3, 0.2)), Vector((0, 0, -0.1)), 40),
    "rear": (Vector((0, 1.2, 0.3)), Vector((0, 0, -0.1)), 40),
}
for name, (loc, look, lens) in views.items():
    cam.location = loc
    cam.rotation_euler = (look - loc).to_track_quat('-Z', 'Y').to_euler()
    cam_data.lens = lens if lens else 28
    sc.render.filepath = "%s_%s.png" % (out_prefix, name)
    bpy.ops.render.render(write_still=True)

# 打印对象清单与材质
for ob in bpy.data.objects:
    if ob.type == 'MESH':
        mats = [m.name if m else "-" for m in ob.data.materials]
        print("MESH %-20s verts=%d mats=%s" % (ob.name, len(ob.data.vertices), mats))
print("DIAG_OK")
