"""Split generated single-mesh weapons into body/magazine/optic without altering geometry."""
import json
import os
import sys
import numpy as np
import trimesh

PROFILES = {
    "em68d": {
        "magazine": lambda c, lo, hi: -0.02 < c[2] < 0.14 and c[1] < -0.055,
        "optic": lambda c, lo, hi: 0.18 < c[2] < 0.30 and c[1] > 0.075,
    },
    "em12g1": {
        "magazine": lambda c, lo, hi: 0.21 < c[2] < 0.32 and c[1] < -0.035,
        "optic": lambda c, lo, hi: 0.07 < c[2] < 0.14 and c[1] > 0.075,
    },
}


def main():
    if len(sys.argv) != 3:
        raise SystemExit("usage: split_generated_weapon.py <em68d|em12g1> <output.glb>")
    kind, output = sys.argv[1], os.path.abspath(sys.argv[2])
    profile = PROFILES[kind]
    source = os.path.abspath(os.path.join("godot/assets/models/weapons", kind + "_viewmodel.glb"))
    scene = trimesh.load(source, force="scene")
    mesh = scene.to_mesh()
    components = mesh.split(only_watertight=False)
    components.sort(key=lambda part: len(part.faces), reverse=True)
    groups = {"body": [], "magazine": [], "optic": []}
    report = {"source": source, "output": output, "faces": len(mesh.faces), "selected": {}}
    for index, part in enumerate(components):
        lo, hi = part.bounds
        center = (lo + hi) * 0.5
        destination = "body"
        if profile["magazine"](center, lo, hi):
            destination = "magazine"
        elif profile["optic"](center, lo, hi):
            destination = "optic"
        groups[destination].append(part)
        if destination != "body":
            report["selected"].setdefault(destination, []).append({
                "index": index, "faces": len(part.faces),
                "lo": lo.tolist(), "hi": hi.tolist(), "center": center.tolist(),
            })
    for name, parts in groups.items():
        if not parts:
            raise RuntimeError("empty part group: " + name)
    os.makedirs(os.path.dirname(output), exist_ok=True)
    out_scene = trimesh.Scene()
    for name, parts in groups.items():
        combined = trimesh.util.concatenate(parts)
        node_name = kind + "_" + name
        if name == "magazine":
            lo, hi = combined.bounds
            pivot = np.array([(lo[0] + hi[0]) * 0.5, hi[1], (lo[2] + hi[2]) * 0.5])
            combined.apply_translation(-pivot)
            transform = trimesh.transformations.translation_matrix(pivot)
            out_scene.add_geometry(combined, node_name=node_name, geom_name=node_name, transform=transform)
            if kind == "em12g1":
                ammo_scene = trimesh.Scene()
                ammo_scene.add_geometry(combined.copy(), node_name=node_name, geom_name=node_name, transform=transform)
                ammo_path = os.path.join("godot/assets/models/weapons/em12g1_magazine.glb")
                ammo_scene.export(ammo_path)
                report["ammo_model"] = ammo_path
        else:
            out_scene.add_geometry(combined, node_name=node_name, geom_name=node_name)
        report[name] = {"faces": len(combined.faces), "bounds": combined.bounds.tolist(), "components": len(parts)}
    out_scene.export(output)
    report["output_faces"] = sum(report[name]["faces"] for name in groups)
    report_path = os.path.splitext(output)[0] + "_report.json"
    with open(report_path, "w", encoding="utf-8") as handle:
        json.dump(report, handle, ensure_ascii=False, indent=2)
    print("SPLIT", kind, report["output_faces"], "->", output)
    print("REPORT", report_path)


if __name__ == "__main__":
    main()
