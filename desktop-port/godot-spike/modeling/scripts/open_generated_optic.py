"""Open the EM-12G-1 optic by subdividing native triangles around the bore."""
import json
import os
import sys
import numpy as np
import trimesh
from trimesh.visual import TextureVisuals


def clip_mesh_to_bore(mesh, center_xy, half_extents, corner_radius, subdivisions=8):
    vertices = []
    faces = []
    uv = []
    half_extents = np.asarray(half_extents, dtype=float)

    def signed_distance(points):
        points = np.asarray(points, dtype=float)
        q = np.abs(points - center_xy) - (half_extents - corner_radius)
        outside = np.linalg.norm(np.maximum(q, 0.0), axis=-1)
        inside = np.minimum(np.maximum(q[..., 0], q[..., 1]), 0.0)
        return outside + inside - corner_radius

    def append_triangle(triangle, triangle_uv, original_area):
        if signed_distance(triangle[:, :2].mean(axis=0)) < 0.0:
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
        if np.all(signed_distance(triangle[:, :2]) < 0.0):
            continue
        original_area = float((triangle[1, 0] - triangle[0, 0]) * (triangle[2, 1] - triangle[0, 1])
                              - (triangle[1, 1] - triangle[0, 1]) * (triangle[2, 0] - triangle[0, 0]))
        triangle_lo = triangle[:, :2].min(axis=0)
        triangle_hi = triangle[:, :2].max(axis=0)
        bore_lo = center_xy - half_extents
        bore_hi = center_xy + half_extents
        if np.any(triangle_hi < bore_lo) or np.any(triangle_lo > bore_hi):
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
    center_xy = np.array((0.00663074, 0.10259105))
    half_extents = np.array((0.014, 0.014))
    corner_radius = 0.0035
    optic = clip_mesh_to_bore(optic, center_xy, half_extents, corner_radius)
    out_scene = trimesh.Scene()
    out_scene.add_geometry(optic, node_name="em12g1_optic", geom_name="em12g1_optic")
    os.makedirs(os.path.dirname(output), exist_ok=True)
    out_scene.export(output)
    report = {
        "source": source,
        "output": output,
        "bore_center_xy": center_xy.tolist(),
        "method": "native_triangle_subdivision_centroid_rounded_rect",
        "subdivisions": 8,
        "bore_half_extents": half_extents.tolist(),
        "bore_corner_radius": corner_radius,
        "faces_before": len(centers),
        "faces_after": len(optic.faces),
    }
    report_path = os.path.splitext(output)[0] + "_report.json"
    with open(report_path, "w", encoding="utf-8") as handle:
        json.dump(report, handle, ensure_ascii=False, indent=2)
    print("OPTIC_BORED", json.dumps(report, ensure_ascii=False))


if __name__ == "__main__":
    main()
