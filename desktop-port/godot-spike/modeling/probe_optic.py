import bpy, sys, json

argv = sys.argv[sys.argv.index("--") + 1:]
src = argv[0]

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)

report = {}
for obj in bpy.data.objects:
    if obj.type != "MESH":
        continue
    mats = []
    for slot in obj.material_slots:
        if slot.material is None:
            continue
        m = slot.material
        info = {"name": m.name}
        if m.use_nodes:
            bsdf = next((n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
            if bsdf:
                info["alpha"] = bsdf.inputs["Alpha"].default_value
                info["base_color"] = list(bsdf.inputs["Base Color"].default_value)
                info["metallic"] = bsdf.inputs["Metallic"].default_value
                info["roughness"] = bsdf.inputs["Roughness"].default_value
                tex = bsdf.inputs["Base Color"].links
                info["has_base_texture"] = len(tex) > 0
        mats.append(info)
    # per-material face counts
    face_counts = [0] * max(1, len(obj.material_slots))
    for poly in obj.data.polygons:
        if poly.material_index < len(face_counts):
            face_counts[poly.material_index] += 1
    report[obj.name] = {
        "verts": len(obj.data.vertices),
        "faces": len(obj.data.polygons),
        "materials": mats,
        "face_counts_per_slot": face_counts,
        "dimensions": list(obj.dimensions),
    }

print("GLBPROBE " + json.dumps(report, indent=1))
