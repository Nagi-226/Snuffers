"""Compute UV tangents and write standard glTF TANGENT accessors."""
import json
import os
import struct
import sys
import numpy as np
import trimesh


def read_glb(path):
    blob = open(path, "rb").read()
    _, _, total = struct.unpack_from("<III", blob, 0)
    offset = 12
    document = None
    binary = b""
    while offset + 8 <= total:
        length, kind = struct.unpack_from("<II", blob, offset)
        offset += 8
        data = blob[offset:offset + length]
        offset += length
        if kind == 0x4E4F534A:
            document = json.loads(data.decode("utf-8"))
        elif kind == 0x004E4942:
            binary = data
    return document, binary


def tangents(mesh):
    count = len(mesh.vertices)
    if count == 0:
        return np.zeros((0, 4), dtype=np.float32)
    uv = mesh.visual.uv
    normals = mesh.vertex_normals
    tan = np.zeros((count, 3), dtype=np.float64)
    bitan = np.zeros((count, 3), dtype=np.float64)
    for tri, face_uv in zip(mesh.vertices[mesh.faces], uv[mesh.faces]):
        e1, e2 = tri[1] - tri[0], tri[2] - tri[0]
        du1, du2 = face_uv[1] - face_uv[0], face_uv[2] - face_uv[0]
        det = du1[0] * du2[1] - du1[1] * du2[0]
        if abs(det) < 1e-12:
            continue
        t = (e1 * du2[1] - e2 * du1[1]) / det
        b = (e2 * du1[0] - e1 * du2[0]) / det
        tan += t
        bitan += b
    result = np.zeros((count, 4), dtype=np.float32)
    for index in range(count):
        normal = normals[index]
        tangent = tan[index] - normal * np.dot(normal, tan[index])
        length = np.linalg.norm(tangent)
        if length < 1e-10:
            axis = np.array([0.0, 0.0, 1.0]) if abs(normal[2]) < 0.9 else np.array([1.0, 0.0, 0.0])
            tangent = np.cross(axis, normal)
            length = np.linalg.norm(tangent)
        tangent /= max(length, 1e-12)
        handedness = 1.0 if np.dot(np.cross(normal, tangent), bitan[index]) >= 0.0 else -1.0
        result[index] = (*tangent, handedness)
    return result


def main():
    path = os.path.abspath(sys.argv[1])
    scene = trimesh.load(path, force="scene")
    computed = {name: tangents(mesh) for name, mesh in scene.geometry.items()}
    document, binary = read_glb(path)
    new_binary = binary
    for mesh in document.get("meshes", []):
        name = mesh.get("name", "")
        values = computed.get(name)
        if values is None:
            raise RuntimeError("missing tangent source for " + name)
        for primitive in mesh["primitives"]:
            position_accessor = document["accessors"][primitive["attributes"]["POSITION"]]
            if int(position_accessor["count"]) != len(values):
                raise RuntimeError("vertex count mismatch for " + name)
            while len(new_binary) % 4:
                new_binary += b"\0"
            view_index = len(document.setdefault("bufferViews", []))
            document["bufferViews"].append({
                "buffer": 0, "byteOffset": len(new_binary), "byteLength": values.nbytes,
            })
            new_binary += values.tobytes()
            accessor_index = len(document["accessors"])
            document["accessors"].append({
                "bufferView": view_index, "componentType": 5126,
                "count": len(values), "type": "VEC4",
            })
            primitive["attributes"]["TANGENT"] = accessor_index
    document["buffers"][0]["byteLength"] = len(new_binary)
    json_bytes = json.dumps(document, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    while len(json_bytes) % 4:
        json_bytes += b" "
    total = 12 + 8 + len(json_bytes) + 8 + len(new_binary)
    with open(path, "wb") as handle:
        handle.write(struct.pack("<III", 0x46546C67, 2, total))
        handle.write(struct.pack("<II", len(json_bytes), 0x4E4F534A))
        handle.write(json_bytes)
        handle.write(struct.pack("<II", len(new_binary), 0x004E4942))
        handle.write(new_binary)
    print("TANGENTS", path, {name: len(values) for name, values in computed.items()})


if __name__ == "__main__":
    main()
