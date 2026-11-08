"""Restore native optic shells and make only a precise sight prism transparent.

All source triangle area is retained. Only triangles crossing the prism boundary
are split; positions, normals, tangents, UVs and embedded textures are preserved.
"""
import copy
import json
import math
import os
import struct
import sys


def read_glb(path):
    data = open(path, "rb").read()
    if data[:4] != b"glTF" or struct.unpack_from("<I", data, 4)[0] != 2:
        raise RuntimeError("expected GLB 2.0")
    json_length = struct.unpack_from("<I", data, 12)[0]
    document = json.loads(data[20:20 + json_length])
    return document, bytearray(data[28 + json_length:])


def read_accessor(document, binary, index):
    accessor = document["accessors"][index]
    view = document["bufferViews"][accessor["bufferView"]]
    width = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[accessor["type"]]
    code = {5126: "f", 5125: "I", 5123: "H", 5121: "B"}[accessor["componentType"]]
    layout = "<" + code * width
    stride = view.get("byteStride", struct.calcsize(layout))
    offset = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    return [struct.unpack_from(layout, binary, offset + index * stride)
            for index in range(accessor["count"])]


def append_accessor(document, binary, values, accessor_type, component_type=5126):
    binary.extend(b"\0" * ((-len(binary)) % 4))
    offset = len(binary)
    code = "f" if component_type == 5126 else "I"
    for value in values:
        binary.extend(struct.pack("<" + code * len(value), *value))
    document["bufferViews"].append({"buffer": 0, "byteOffset": offset, "byteLength": len(binary) - offset})
    accessor = {"bufferView": len(document["bufferViews"]) - 1,
                "componentType": component_type, "count": len(values), "type": accessor_type}
    if accessor_type == "VEC3":
        accessor["min"] = [min(value[axis] for value in values) for axis in range(3)]
        accessor["max"] = [max(value[axis] for value in values) for axis in range(3)]
    document["accessors"].append(accessor)
    return len(document["accessors"]) - 1


def write_glb(path, document, binary):
    binary.extend(b"\0" * ((-len(binary)) % 4))
    document["buffers"][0]["byteLength"] = len(binary)
    payload = json.dumps(document, separators=(",", ":")).encode("utf-8")
    payload += b" " * ((-len(payload)) % 4)
    data = (struct.pack("<4sII", b"glTF", 2, 28 + len(payload) + len(binary))
            + struct.pack("<I4s", len(payload), b"JSON") + payload
            + struct.pack("<I4s", len(binary), b"BIN\0") + binary)
    with open(path, "wb") as handle:
        handle.write(data)


def split_polygon(polygon, normal, distance):
    inside, outside = [], []
    for index, start in enumerate(polygon):
        end = polygon[(index + 1) % len(polygon)]
        start_distance = sum(normal[axis] * start["POSITION"][axis] for axis in range(3)) - distance
        end_distance = sum(normal[axis] * end["POSITION"][axis] for axis in range(3)) - distance
        (inside if start_distance <= 0.0 else outside).append(start)
        if (start_distance < 0.0 < end_distance) or (end_distance < 0.0 < start_distance):
            weight = start_distance / (start_distance - end_distance)
            crossing = {name: tuple(a + (b - a) * weight for a, b in zip(start[name], end[name]))
                        for name in start}
            inside.append(crossing)
            outside.append(crossing)
    return inside, outside


def triangle_area(triangle):
    a, b, c = [vertex["POSITION"] for vertex in triangle]
    u, v = [b[axis] - a[axis] for axis in range(3)], [c[axis] - a[axis] for axis in range(3)]
    cross = (u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0])
    return math.sqrt(sum(value * value for value in cross)) * 0.5


def restore_optic(model, source, output):
    center_y, radius, depth = {"em57s2": (0.165, 0.016, (-0.34, -0.20)),
                               "em86m": (0.180, 0.018, (-0.23, 0.17))}[model]
    document, binary = read_glb(source)
    planes = [((math.cos(index * math.tau / 16), math.sin(index * math.tau / 16), 0.0),
               radius + center_y * math.sin(index * math.tau / 16)) for index in range(16)]
    planes += [((0.0, 0.0, 1.0), depth[1]), ((0.0, 0.0, -1.0), -depth[0])]
    native_area = restored_area = 0.0
    native_triangles = opaque_triangles = lens_triangles = 0
    for mesh in document["meshes"]:
        output_primitives = []
        for primitive in mesh["primitives"]:
            attributes = {name: read_accessor(document, binary, index)
                          for name, index in primitive["attributes"].items()}
            source_indices = [value[0] for value in read_accessor(document, binary, primitive["indices"])]
            output_attributes = {name: [] for name in attributes}
            opaque_indices, lens_indices = [], []

            def append_polygon(polygon, indices):
                nonlocal restored_area
                for corner in range(1, len(polygon) - 1):
                    triangle = [polygon[0], polygon[corner], polygon[corner + 1]]
                    area = triangle_area(triangle)
                    if area <= 1e-15:
                        continue
                    restored_area += area
                    for vertex in triangle:
                        indices.append((len(output_attributes["POSITION"]),))
                        for name in output_attributes:
                            output_attributes[name].append(vertex[name])

            for start in range(0, len(source_indices), 3):
                polygon = [{name: values[index] for name, values in attributes.items()}
                           for index in source_indices[start:start + 3]]
                native_triangles += 1
                native_area += triangle_area(polygon)
                positions = [vertex["POSITION"] for vertex in polygon]
                if (max(value[0] for value in positions) < -radius
                        or min(value[0] for value in positions) > radius
                        or max(value[1] for value in positions) < center_y - radius
                        or min(value[1] for value in positions) > center_y + radius
                        or max(value[2] for value in positions) < depth[0]
                        or min(value[2] for value in positions) > depth[1]):
                    append_polygon(polygon, opaque_indices)
                    continue
                for normal, distance in planes:
                    polygon, outside = split_polygon(polygon, normal, distance)
                    append_polygon(outside, opaque_indices)
                    if len(polygon) < 3:
                        break
                if len(polygon) >= 3:
                    append_polygon(polygon, lens_indices)

            if not lens_indices:
                raise RuntimeError("no native sight-covering surfaces found")
            attribute_indices = {name: append_accessor(document, binary, values,
                                  document["accessors"][primitive["attributes"][name]]["type"])
                                 for name, values in output_attributes.items()}
            glass = copy.deepcopy(document["materials"][primitive["material"]])
            glass["name"] = model.upper() + "_Native_Sight_Glass"
            glass["alphaMode"] = "BLEND"
            glass["pbrMetallicRoughness"]["baseColorFactor"] = [0.035, 0.32, 0.48, 0.02]
            glass["pbrMetallicRoughness"]["metallicFactor"] = 0.0
            glass["pbrMetallicRoughness"]["roughnessFactor"] = 0.12
            document["materials"].append(glass)
            for indices, material in [(opaque_indices, primitive["material"]),
                                      (lens_indices, len(document["materials"]) - 1)]:
                part = copy.deepcopy(primitive)
                part["attributes"] = attribute_indices
                part["indices"] = append_accessor(document, binary, indices, "SCALAR", 5125)
                part["material"] = material
                output_primitives.append(part)
            opaque_triangles += len(opaque_indices) // 3
            lens_triangles += len(lens_indices) // 3
        mesh["primitives"] = output_primitives
    if abs(native_area - restored_area) > native_area * 1e-9:
        raise RuntimeError("source surface area was not fully preserved")
    write_glb(output, document, binary)
    print(json.dumps({"model": model, "native_triangles": native_triangles,
                      "opaque_triangles": opaque_triangles, "lens_triangles": lens_triangles,
                      "native_surface_area": native_area, "restored_surface_area": restored_area,
                      "aperture_center_xy": [0.0, center_y], "aperture_radius": radius,
                      "aperture_depth": depth, "faces_deleted": 0,
                      "output_bytes": os.path.getsize(output)}, indent=2))


if __name__ == "__main__":
    if len(sys.argv) != 4 or sys.argv[1] not in {"em57s2", "em86m"}:
        raise SystemExit("usage: restore_optic_shells.py <em57s2|em86m> <intact.glb> <ads.glb>")
    restore_optic(sys.argv[1], os.path.abspath(sys.argv[2]), os.path.abspath(sys.argv[3]))
