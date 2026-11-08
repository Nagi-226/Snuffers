"""Extract original EM-57S-2 tail components with UVs and materials for identification."""
import bpy
import bmesh
import mathutils
import os
import sys

def component_roots(mesh):
    parent = list(range(len(mesh.vertices)))
    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a
    for edge in mesh.edges:
        ra, rb = find(edge.vertices[0]), find(edge.vertices[1])
        if ra != rb:
            parent[ra] = rb
    return [find(i) for i in range(len(mesh.vertices))]


def component_stats(mesh, roots):
    stats = {}
    for poly in mesh.polygons:
        root = roots[poly.vertices[0]]
        st = stats.setdefault(root, {"tris": 0, "verts": 0, "lo": [1e9] * 3, "hi": [-1e9] * 3})
        st["tris"] += len(poly.vertices) - 2
        for vi in poly.vertices:
            co = mesh.vertices[vi].co
            for k in range(3):
                st["lo"][k] = min(st["lo"][k], co[k])
                st["hi"][k] = max(st["hi"][k], co[k])
    for vertex in mesh.vertices:
        stats[roots[vertex.index]]["verts"] += 1
    return stats

SRC = os.path.abspath(sys.argv[sys.argv.index("--") + 1])
OUT = os.path.abspath(sys.argv[sys.argv.index("--") + 2])
os.makedirs(OUT, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
obj = next(o for o in bpy.context.scene.objects if o.type == "MESH")
roots = component_roots(obj.data)
stats = component_stats(obj.data, roots)
candidates = []
for root, st in stats.items():
    cy = (st["lo"][1] + st["hi"][1]) * 0.5
    cz = (st["lo"][2] + st["hi"][2]) * 0.5
    if st["tris"] >= 100 and abs(cy) > 0.34 and abs(cz) < 0.08:
        candidates.append((root, cy, st))
candidates.sort(key=lambda item: item[1])
print("CANDIDATES", len(candidates), flush=True)

scene = bpy.context.scene
scene.render.engine = "BLENDER_WORKBENCH"
scene.render.resolution_x = 700
scene.render.resolution_y = 700
scene.render.resolution_percentage = 100
scene.display.shading.light = "STUDIO"
scene.display.shading.color_type = "TEXTURE"
cam_data = bpy.data.cameras.new("inspect_cam")
cam_data.type = "ORTHO"
cam = bpy.data.objects.new("inspect_cam", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam

for index, (root, cy, st) in enumerate(candidates):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if roots[f.verts[0].index] != root], context="FACES")
    mesh = bpy.data.meshes.new("tail_%02d" % index)
    bm.to_mesh(mesh)
    bm.free()
    part = bpy.data.objects.new("tail_%02d" % index, mesh)
    scene.collection.objects.link(part)
    part.matrix_world = obj.matrix_world.copy()
    for material in obj.data.materials:
        mesh.materials.append(material)
    bpy.context.view_layer.update()
    print(index, "root", root, "tris", st["tris"], "lo", st["lo"], "hi", st["hi"], flush=True)
    path = os.path.join(OUT, "tail_%02d.glb" % index)
    bpy.ops.object.select_all(action="DESELECT")
    part.select_set(True)
    bpy.context.view_layer.objects.active = part
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_animations=False)
    points = [part.matrix_world @ v.co for v in mesh.vertices]
    lo = mathutils.Vector(tuple(min(p[i] for p in points) for i in range(3)))
    hi = mathutils.Vector(tuple(max(p[i] for p in points) for i in range(3)))
    center = (lo + hi) * 0.5
    size = max(hi - lo)
    cam_data.ortho_scale = size * 1.35
    for label, direction in [("rear", (0, -1, 0)), ("front", (0, 1, 0))]:
        cam.location = center + mathutils.Vector(direction) * size * 3
        cam.rotation_euler = (center - cam.location).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = os.path.join(OUT, "tail_%02d_%s.png" % (index, label))
        bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(part, do_unlink=True)
print("DONE", flush=True)
