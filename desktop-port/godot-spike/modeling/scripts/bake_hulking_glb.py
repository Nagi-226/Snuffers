import json
import math
import struct
import sys


def quat_mul(a, b):
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return (
        aw * bx + ax * bw + ay * bz - az * by,
        aw * by - ax * bz + ay * bw + az * bx,
        aw * bz + ax * by - ay * bx + az * bw,
        aw * bw - ax * bx - ay * by - az * bz,
    )


def quat_euler(x=0.0, y=0.0, z=0.0):
    qx = (math.sin(x * 0.5), 0.0, 0.0, math.cos(x * 0.5))
    qy = (0.0, math.sin(y * 0.5), 0.0, math.cos(y * 0.5))
    qz = (0.0, 0.0, math.sin(z * 0.5), math.cos(z * 0.5))
    return quat_mul(quat_mul(qz, qy), qx)


def normalized(q):
    length = math.sqrt(sum(value * value for value in q))
    return tuple(value / length for value in q)


def animation_definitions():
    return {
        "idle": (1.6, {
            0.0: {"chest": (0, 0, 0)},
            0.8: {"chest": (0.025, 0.02, 0)},
            1.6: {"chest": (0, 0, 0)},
        }),
        "walk": (1.6, {
            0.0: {"thigh_r": (0.45, 0, 0), "thigh_l": (-0.45, 0, 0), "upper_arm_r": (-0.22, 0, 0), "upper_arm_l": (0.22, 0, 0)},
            0.8: {"thigh_r": (-0.45, 0, 0), "thigh_l": (0.45, 0, 0), "upper_arm_r": (0.22, 0, 0), "upper_arm_l": (-0.22, 0, 0)},
            1.6: {"thigh_r": (0.45, 0, 0), "thigh_l": (-0.45, 0, 0), "upper_arm_r": (-0.22, 0, 0), "upper_arm_l": (0.22, 0, 0)},
        }),
        "attack": (2.4, {
            0.0: {"upper_arm_r": (0, 0, 0), "forearm_r": (0, 0, 0), "chest": (0, 0, 0)},
            0.85: {"upper_arm_r": (-1.75, 0.1, -0.35), "forearm_r": (-0.85, 0, 0), "chest": (-0.18, 0, -0.4)},
            1.25: {"upper_arm_r": (1.65, 0, 0.45), "forearm_r": (0.95, 0, 0), "chest": (0.5, 0, 0.35)},
            1.6: {"upper_arm_r": (1.65, 0, 0.45), "forearm_r": (0.95, 0, 0), "chest": (0.5, 0, 0.35)},
            2.4: {"upper_arm_r": (0, 0, 0), "forearm_r": (0, 0, 0), "chest": (0, 0, 0)},
        }),
        "death": (2.4, {
            0.0: {"hips": (0, 0, 0), "upper_arm_r": (0, 0, 0)},
            2.4: {"hips": (1.35, 0, 0), "upper_arm_r": (0.8, 0, 0)},
        }),
    }


def main():
    source, output = sys.argv[1:3]
    with open(source, "rb") as handle:
        data = handle.read()
    json_length, json_type = struct.unpack_from("<II", data, 12)
    assert json_type == 0x4E4F534A
    document = json.loads(data[20:20 + json_length])
    bin_header = 20 + json_length
    bin_length, bin_type = struct.unpack_from("<II", data, bin_header)
    assert bin_type == 0x004E4942
    binary = bytearray(data[bin_header + 8:bin_header + 8 + bin_length])

    def append_accessor(values, accessor_type):
        while len(binary) % 4:
            binary.append(0)
        offset = len(binary)
        binary.extend(values)
        view_index = len(document["bufferViews"])
        document["bufferViews"].append({"buffer": 0, "byteOffset": offset, "byteLength": len(values)})
        accessor_index = len(document["accessors"])
        count = len(values) // (4 * {"SCALAR": 1, "VEC3": 3, "VEC4": 4}[accessor_type])
        document["accessors"].append({
            "bufferView": view_index,
            "componentType": 5126,
            "count": count,
            "type": accessor_type,
        })
        return accessor_index

    nodes = document["nodes"]
    rest_rotations = [tuple(node.get("rotation", (0, 0, 0, 1))) for node in nodes]
    animations = []
    for name, (duration, poses) in animation_definitions().items():
        times = sorted(poses)
        time_accessor = append_accessor(struct.pack("<%df" % len(times), *times), "SCALAR")
        samplers = []
        channels = []
        for node_index, rest in enumerate(rest_rotations):
            rotations = []
            for time in times:
                euler = poses[time].get(nodes[node_index].get("name"), (0, 0, 0))
                rotations.extend(normalized(quat_mul(rest, quat_euler(*euler))))
            output_accessor = append_accessor(struct.pack("<%df" % len(rotations), *rotations), "VEC4")
            samplers.append({"input": time_accessor, "interpolation": "LINEAR", "output": output_accessor})
            channels.append({"sampler": len(samplers) - 1, "target": {"node": node_index, "path": "rotation"}})
        animations.append({"name": name, "samplers": samplers, "channels": channels})
    document["animations"] = animations
    document["buffers"][0]["byteLength"] = len(binary)
    json_bytes = json.dumps(document, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    while len(json_bytes) % 4:
        json_bytes += b" "
    result = bytearray()
    result.extend(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(json_bytes) + 8 + len(binary)))
    result.extend(struct.pack("<II", len(json_bytes), 0x4E4F534A))
    result.extend(json_bytes)
    result.extend(struct.pack("<II", len(binary), 0x004E4942))
    result.extend(binary)
    with open(output, "wb") as handle:
        handle.write(result)
    print("HULKING_BAKE", output, "animations", [(name, len(definition[1])) for name, definition in animation_definitions().items()])


if __name__ == "__main__":
    main()
