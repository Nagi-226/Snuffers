"""Open the EM-12G-1 optic by subdividing native triangles around the bore."""
import json
import os
import struct
import sys
import numpy as np
import trimesh
from trimesh.visual import TextureVisuals


def add_tangents(mesh):
    tangents = np.zeros((len(mesh.vertices), 4), dtype=np.float32)
    for face_index, face in enumerate(mesh.faces):
        positions = mesh.vertices[face]
        uv = mesh.visual.uv[face]
        edge_1 = positions[1] - positions[0]
        edge_2 = positions[2] - positions[0]
        delta_1 = uv[1] - uv[0]
        delta_2 = uv[2] - uv[0]
        determinant = delta_1[0] * delta_2[1] - delta_1[1] * delta_2[0]
        if abs(determinant) > 1e-12:
            tangent = (edge_1 * delta_2[1] - edge_2 * delta_1[1]) / determinant
            bitangent = (edge_2 * delta_1[0] - edge_1 * delta_2[0]) / determinant
        else:
            tangent = edge_1
            bitangent = edge_2
        for corner, vertex_index in enumerate(face):
            normal = mesh.vertex_normals[vertex_index]
            orthogonal = tangent - normal * float(np.dot(normal, tangent))
            length = float(np.linalg.norm(orthogonal))
            if length < 1e-12:
                axis = np.array((0.0, 0.0, 1.0)) if abs(normal[2]) < 0.9 else np.array((1.0, 0.0, 0.0))
                orthogonal = np.cross(axis, normal)
                length = float(np.linalg.norm(orthogonal))
            direction = orthogonal / length
            handedness = -1.0 if np.dot(np.cross(normal, direction), bitangent) < 0.0 else 1.0
            tangents[vertex_index] = (*direction, handedness)
    mesh.vertex_attributes["TANGENT"] = tangents


def standardize_tangent_attribute(path):
    with open(path, "rb") as handle:
        data = handle.read()
    json_length, json_type = struct.unpack_from("<I4s", data, 12)
    if json_type != b"JSON":
        raise RuntimeError("GLB JSON chunk missing")
    document = json.loads(data[20:20 + json_length])
    changed = False
    for mesh in document.get("meshes", []):
        for primitive in mesh.get("primitives", []):
            attributes = primitive.get("attributes", {})
            if "_TANGENT" in attributes:
                attributes["TANGENT"] = attributes.pop("_TANGENT")
                changed = True
    if not changed:
        raise RuntimeError("exported tangent attribute missing")
    payload = json.dumps(document, separators=(",", ":")).encode("utf-8")
    payload += b" " * ((-len(payload)) % 4)
    remainder = data[20 + json_length:]
    header = struct.pack("<4sII", b"glTF", 2, 20 + len(payload) + len(remainder))
    with open(path, "wb") as handle:
        handle.write(header + struct.pack("<I4s", len(payload), b"JSON") + payload + remainder)


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
    add_tangents(result)
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
    center_xy = np.array((0.00125, 0.10025))
    half_extents = np.array((0.02075, 0.01375))
    corner_radius = 0.0
    optic = clip_mesh_to_bore(optic, center_xy, half_extents, corner_radius)
    out_scene = trimesh.Scene()
    out_scene.add_geometry(optic, node_name="em12g1_optic", geom_name="em12g1_optic")
    os.makedirs(os.path.dirname(output), exist_ok=True)
    out_scene.export(output)
    standardize_tangent_attribute(output)
    report = {
        "source": source,
        "output": output,
        "bore_center_xy": center_xy.tolist(),
        "method": "native_triangle_subdivision_centroid_rect",
        "subdivisions": 8,
        "bore_half_extents": half_extents.tolist(),
        "bore_corner_radius": corner_radius,
        "bore_bounds_xy": [(center_xy - half_extents).tolist(), (center_xy + half_extents).tolist()],
        "faces_before": len(centers),
        "faces_after": len(optic.faces),
    }
    report_path = os.path.splitext(output)[0] + "_report.json"
    with open(report_path, "w", encoding="utf-8") as handle:
        json.dump(report, handle, ensure_ascii=False, indent=2)
    print("OPTIC_BORED", json.dumps(report, ensure_ascii=False))


if __name__ == "__main__":
    main()
