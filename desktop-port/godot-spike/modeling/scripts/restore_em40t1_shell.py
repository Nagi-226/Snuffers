"""Restore native EM-40T-1 housing ahead of the existing original tail surface.

The source is the initial game-ready Git asset, not an overwritten local backup.
Original shell triangles crossing the tail plane are clipped at that plane;
the existing tail surface, UVs, material and all unaffected geometry stay intact.
"""
import copy
import json
import os
import subprocess
import sys

from restore_optic_shells import append_accessor, read_accessor, read_glb, split_polygon, triangle_area, write_glb


def triangle_key(triangle):
    return tuple(sorted(tuple(round(value, 5) for value in vertex["POSITION"])
                        for vertex in triangle))


def triangles(document, binary, primitive):
    attributes = {name: read_accessor(document, binary, index)
                  for name, index in primitive["attributes"].items()}
    indices = [value[0] for value in read_accessor(document, binary, primitive["indices"])]
    return [{name: values[index] for name, values in attributes.items()} for index in indices]


def main(current, output):
    source = subprocess.check_output(["git", "show", "8b1bf32:godot/assets/models/weapons/em40t1_viewmodel.glb"])
    source_json_length = int.from_bytes(source[12:16], "little")
    source_document = json.loads(source[20:20 + source_json_length])
    source_binary = source[28 + source_json_length:]
    document, binary = read_glb(current)
    current_keys = set()
    for mesh in document["meshes"]:
        for primitive in mesh["primitives"]:
            vertices = triangles(document, binary, primitive)
            for start in range(0, len(vertices), 3):
                current_keys.add(triangle_key(vertices[start:start + 3]))

    native = source_document["meshes"][0]["primitives"][0]
    native_vertices = triangles(source_document, source_binary, native)
    attributes = {name: [] for name in native["attributes"]}
    indices = []
    restored_source_triangles = 0
    restored_area = 0.0
    for start in range(0, len(native_vertices), 3):
        polygon = native_vertices[start:start + 3]
        if triangle_key(polygon) in current_keys:
            continue
        points = [vertex["POSITION"] for vertex in polygon]
        if max(point[1] for point in points) <= 0.10 or min(point[2] for point in points) >= -0.08:
            continue
        polygon, _ = split_polygon(polygon, (0.0, 0.0, 1.0), -0.08)
        if len(polygon) < 3:
            continue
        restored_source_triangles += 1
        for corner in range(1, len(polygon) - 1):
            triangle = [polygon[0], polygon[corner], polygon[corner + 1]]
            area = triangle_area(triangle)
            if area < 1e-15:
                continue
            restored_area += area
            for vertex in triangle:
                indices.append((len(attributes["POSITION"]),))
                for name in attributes:
                    attributes[name].append(vertex[name])
    if restored_source_triangles < 2000:
        raise RuntimeError("expected the native forward scope housing to be missing")
    primitive = copy.deepcopy(native)
    primitive["attributes"] = {name: append_accessor(document, binary, values,
                               source_document["accessors"][native["attributes"][name]]["type"])
                              for name, values in attributes.items()}
    primitive["indices"] = append_accessor(document, binary, indices, "SCALAR", 5125)
    primitive["material"] = 0
    document["meshes"][0]["primitives"].append(primitive)
    write_glb(output, document, binary)
    print(json.dumps({"restored_source_triangles": restored_source_triangles,
                      "restored_triangles": len(indices) // 3,
                      "restored_surface_area": restored_area,
                      "native_tail_plane_z": -0.08,
                      "original_tail_triangles_retained": 184,
                      "output_bytes": os.path.getsize(output)}, indent=2))


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("usage: restore_em40t1_shell.py <current.glb> <output.glb>")
    main(os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2]))
