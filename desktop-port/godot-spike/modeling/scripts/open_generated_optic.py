"""Open the EM-12G-1 optic by subdividing native triangles around the bore."""
import json
import os
import sys
import numpy as np
import trimesh
from trimesh.visual import TextureVisuals


def clip_mesh_to_bore(mesh, center_xy, radius, subdivisions=8):
    vertices = []
    faces = []
    uv = []

    def edge_intersects(a, b):
        direction = b[:2] - a[:2]
        offset = a[:2] - center_xy
        qa = float(np.dot(direction, direction))
        qb = 2.0 * float(np.dot(offset, direction))
        qc = float(np.dot(offset, offset)) - radius * radius
        return qb * qb - 4.0 * qa * qc > 0.0

    def append_triangle(triangle, triangle_uv, original_area):
        if np.linalg.norm(triangle[:, :2].mean(axis=0) - center_xy) < radius:
            return
        clipped_area = float((triangle[1, 0] - triangle[0, 0]) * (triangle[2, 1] - triangle[0, 1])
                             - (triangle[1, 1] - triangle[0, 1]) * (triangle[2, 0] - triangle[0, 0]))
        if abs(clipped_area) < 1e-16:
            return
        start = len(vertices)
        order = [2, 1, 0] if (clipped_area < 0.0) != (original_area < 0.0) else [0, 1, 2]
        for index in order:
            vertices.append(triangle[index])
            uv.append(triangle_uv[index])
        faces.append([start, start + 1, start + 2])

    for face in mesh.faces:
        triangle = mesh.vertices[face]
        triangle_uv = mesh.visual.uv[face]
        distances = np.linalg.norm(triangle[:, :2] - center_xy, axis=1)
        if np.all(distances < radius):
            continue
        original_area = float((triangle[1, 0] - triangle[0, 0]) * (triangle[2, 1] - triangle[0, 1])
                              - (triangle[1, 1] - triangle[0, 1]) * (triangle[2, 0] - triangle[0, 0]))
        intersects = any(edge_intersects(triangle[first], triangle[second]) for first, second in [(0, 1), (1, 2), (2, 0)])
        if not intersects and np.all(distances >= radius):
            basis = np.column_stack((triangle[1, :2] - triangle[0, :2], triangle[2, :2] - triangle[0, :2]))
            center_weights = np.linalg.lstsq(basis, center_xy - triangle[0, :2], rcond=None)[0]
            if not (np.all(center_weights >= -1e-8) and center_weights.sum() <= 1.0 + 1e-8):
                append_triangle(triangle, triangle_uv, original_area)
                continue
        for i in range(subdivisions):
            for j in range(subdivisions - i):
                p00 = triangle[0] + (triangle[1] - triangle[0]) * (i / subdivisions) + (triangle[2] - triangle[0]) * (j / subdivisions)
                p10 = triangle[0] + (triangle[1] - triangle[0]) * ((i + 1) / subdivisions) + (triangle[2] - triangle[0]) * (j / subdivisions)
                p01 = triangle[0] + (triangle[1] - triangle[0]) * (i / subdivisions) + (triangle[2] - triangle[0]) * ((j + 1) / subdivisions)
                uv00 = triangle_uv[0] + (triangle_uv[1] - triangle_uv[0]) * (i / subdivisions) + (triangle_uv[2] - triangle_uv[0]) * (j / subdivisions)
                uv10 = triangle_uv[0] + (triangle_uv[1] - triangle_uv[0]) * ((i + 1) / subdivisions) + (triangle_uv[2] - triangle_uv[0]) * (j / subdivisions)
                uv01 = triangle_uv[0] + (triangle_uv[1] - triangle_uv[0]) * (i / subdivisions) + (triangle_uv[2] - triangle_uv[0]) * ((j + 1) / subdivisions)
                append_triangle(np.array([p00, p10, p01]), np.array([uv00, uv10, uv01]), original_area)
                if i + j < subdivisions - 1:
                    p11 = triangle[0] + (triangle[1] - triangle[0]) * ((i + 1) / subdivisions) + (triangle[2] - triangle[0]) * ((j + 1) / subdivisions)
                    uv11 = triangle_uv[0] + (triangle_uv[1] - triangle_uv[0]) * ((i + 1) / subdivisions) + (triangle_uv[2] - triangle_uv[0]) * ((j + 1) / subdivisions)
                    append_triangle(np.array([p10, p11, p01]), np.array([uv10, uv11, uv01]), original_area)
    result = trimesh.Trimesh(vertices=np.array(vertices), faces=np.array(faces), process=False)
    result.visual = TextureVisuals(uv=np.array(uv), material=mesh.visual.material)
    return result


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
    radius = 0.014
    optic = clip_mesh_to_bore(optic, center_xy, radius)
    out_scene = trimesh.Scene()
    out_scene.add_geometry(optic, node_name="em12g1_optic", geom_name="em12g1_optic")
    os.makedirs(os.path.dirname(output), exist_ok=True)
    out_scene.export(output)
    report = {
        "source": source,
        "output": output,
        "bore_center_xy": list(center_xy),
        "method": "native_triangle_subdivision_centroid",
        "subdivisions": 8,
        "bore_radius": radius,
        "faces_before": len(centers),
        "faces_after": len(optic.faces),
    }
    report_path = os.path.splitext(output)[0] + "_report.json"
    with open(report_path, "w", encoding="utf-8") as handle:
        json.dump(report, handle, ensure_ascii=False, indent=2)
    print("OPTIC_BORED", json.dumps(report, ensure_ascii=False))


if __name__ == "__main__":
    main()
