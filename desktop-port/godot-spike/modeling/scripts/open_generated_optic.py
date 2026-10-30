"""Open the EM-12G-1 optic using only its native lens/back-cover faces."""
import json
import os
import sys
import numpy as np
import trimesh


def main():
    if len(sys.argv) != 3:
        raise SystemExit("usage: open_generated_optic.py <split_weapon.glb> <optic_bored.glb>")
    source, output = map(os.path.abspath, sys.argv[1:])
    scene = trimesh.load(source, force="scene")
    optic = scene.geometry["em12g1_optic"].copy()
    lo, hi = optic.bounds
    cx = (lo[0] + hi[0]) * 0.5
    centers = optic.triangles_center
    normals = optic.face_normals
    axial = (np.abs(normals[:, 2]) > 0.8) & (np.abs(centers[:, 0] - cx) < 0.3 * (hi[0] - lo[0]))
    estimates = centers[axial]
    if len(estimates) <= 50:
        raise RuntimeError("too few axial faces to estimate bore: %d" % len(estimates))
    center_xy = (0.00663074, 0.10259105)
    radius = float(np.max(np.abs(estimates[:, 0] - cx)) * 0.78)
    radial = (centers[:, 0] - center_xy[0]) ** 2 + (centers[:, 1] - center_xy[1]) ** 2
    remove = (radial < radius ** 2) & (np.abs(normals[:, 2]) > 0.8)
    if not 0 < int(remove.sum()) < len(optic.faces) * 0.45:
        raise RuntimeError("unsafe bore face count: %d / %d" % (remove.sum(), len(optic.faces)))
    optic.update_faces(~remove)
    optic.remove_unreferenced_vertices()
    parts = optic.split(only_watertight=False)
    largest_faces = max(len(part.faces) for part in parts)
    kept = []
    inner_faces = 0
    for part in parts:
        center = part.bounds.mean(axis=0)
        inner_radial = (center[0] - center_xy[0]) ** 2 + (center[1] - center_xy[1]) ** 2
        if len(part.faces) < largest_faces and inner_radial < radius ** 2 and center[2] > 0.09:
            part_centers = part.triangles_center
            part_radial = (part_centers[:, 0] - center_xy[0]) ** 2 + (part_centers[:, 1] - center_xy[1]) ** 2
            part_remove = (part_radial < radius ** 2) & (part_centers[:, 2] > 0.09)
            inner_faces += int(part_remove.sum())
            part.update_faces(~part_remove)
            part.remove_unreferenced_vertices()
            if len(part.faces) > 0:
                kept.append(part)
            continue
        kept.append(part)
    optic = trimesh.util.concatenate(kept)
    out_scene = trimesh.Scene()
    out_scene.add_geometry(optic, node_name="em12g1_optic", geom_name="em12g1_optic")
    os.makedirs(os.path.dirname(output), exist_ok=True)
    out_scene.export(output)
    report = {
        "source": source,
        "output": output,
        "bore_center_xy": list(center_xy),
        "method": "native_lens_back_cover_and_bore_faces",
        "bore_radius": radius,
        "inner_component_faces": inner_faces,
        "faces_before": len(centers),
        "faces_after": len(optic.faces),
        "deleted": int(remove.sum()) + inner_faces,
    }
    report_path = os.path.splitext(output)[0] + "_report.json"
    with open(report_path, "w", encoding="utf-8") as handle:
        json.dump(report, handle, ensure_ascii=False, indent=2)
    print("OPTIC_BORED", json.dumps(report, ensure_ascii=False))


if __name__ == "__main__":
    main()
