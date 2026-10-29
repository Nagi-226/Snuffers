"""Open the EM-12G-1 optic and rebuild a smooth, unbroken bore sleeve."""
import json
import os
import sys
import numpy as np
import trimesh
from trimesh.visual import TextureVisuals


def rounded_loop(half_x, half_y, corner, center_xy):
    points = []
    corners = [
        (half_x - corner, half_y - corner, 0.0),
        (-half_x + corner, half_y - corner, 90.0),
        (-half_x + corner, -half_y + corner, 180.0),
        (half_x - corner, -half_y + corner, 270.0),
    ]
    for cx, cy, start in corners:
        for step in range(16):
            angle = np.deg2rad(start + step * 90.0 / 16.0)
            points.append([center_xy[0] + cx + corner * np.cos(angle),
                           center_xy[1] + cy + corner * np.sin(angle)])
    return points


def make_bore_sleeve(optic, center_xy):
    segments = 64
    front_z = 0.1211
    back_z = 0.1291
    outer = rounded_loop(0.024, 0.019, 0.005, center_xy)
    inner = rounded_loop(0.0165, 0.0125, 0.004, center_xy)
    vertices = []
    uv = []
    for index in range(segments):
        for point, z in [(outer[index], front_z), (outer[index], back_z),
                         (inner[index], front_z), (inner[index], back_z)]:
            x, y = point
            vertices.append([x, y, z])
            radial = np.linalg.norm([x - center_xy[0], y - center_xy[1]]) / 0.024
            uv.append([index / segments, radial + (z - front_z) / (back_z - front_z)])
    faces = []
    for index in range(segments):
        nxt = (index + 1) % segments
        of_i, ob_i, inf_i, inb_i = [index * 4 + offset for offset in range(4)]
        of_j, ob_j, inf_j, inb_j = [nxt * 4 + offset for offset in range(4)]
        faces.extend([
            [ob_i, ob_j, inb_j], [ob_i, inb_j, inb_i],
            [of_i, inf_j, of_j], [of_i, inf_i, inf_j],
            [inf_i, inb_j, inf_j], [inf_i, inb_i, inb_j],
            [of_i, of_j, ob_j], [of_i, ob_j, ob_i],
        ])
    sleeve = trimesh.Trimesh(vertices=np.array(vertices), faces=np.array(faces), process=False)
    sleeve.visual = TextureVisuals(uv=np.array(uv), material=optic.visual.material)
    return sleeve


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
    clear_radius = max(radius, 0.0215)
    radial = (centers[:, 0] - center_xy[0]) ** 2 + (centers[:, 1] - center_xy[1]) ** 2
    remove = radial < clear_radius ** 2
    if not 0 < int(remove.sum()) < len(optic.faces) * 0.45:
        raise RuntimeError("unsafe bore face count: %d / %d" % (remove.sum(), len(optic.faces)))
    optic.update_faces(~remove)
    optic.remove_unreferenced_vertices()
    optic = trimesh.util.concatenate([optic, make_bore_sleeve(optic, center_xy)])
    out_scene = trimesh.Scene()
    out_scene.add_geometry(optic, node_name="em12g1_optic", geom_name="em12g1_optic")
    os.makedirs(os.path.dirname(output), exist_ok=True)
    out_scene.export(output)
    report = {
        "source": source,
        "output": output,
        "bore_center_xy": list(center_xy),
        "bore_shape": "rounded_rect",
        "bore_inner_size_xy": [0.033, 0.025],
        "sleeve_outer_size_xy": [0.048, 0.038],
        "clear_radius": clear_radius,
        "sleeve_segments": 64,
        "faces_before": len(centers),
        "faces_after": len(optic.faces),
        "deleted": int(remove.sum()),
    }
    report_path = os.path.splitext(output)[0] + "_report.json"
    with open(report_path, "w", encoding="utf-8") as handle:
        json.dump(report, handle, ensure_ascii=False, indent=2)
    print("OPTIC_BORED", json.dumps(report, ensure_ascii=False))


if __name__ == "__main__":
    main()
