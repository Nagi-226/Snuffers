"""Rebind the existing hulking mesh and bake connected, ground-matched actions.

This follows bake_hulking_glb.py's direct GLB authoring pattern. Original UVs,
indices, materials and image bytes stay unchanged; only this enemy is derived.
Run with the bundled Python runtime: repair_hulking_rig.py <source> <output>.
"""
import hashlib
import json
import math
import re
import struct
import sys
from pathlib import Path


def add(a, b):
    return tuple(x + y for x, y in zip(a, b))


def sub(a, b):
    return tuple(x - y for x, y in zip(a, b))


def mul(v, amount):
    return tuple(x * amount for x in v)


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def length(v):
    return math.sqrt(dot(v, v))


def unit(v):
    distance = length(v)
    if distance < 1e-9:
        raise ValueError("zero bone direction")
    return mul(v, 1.0 / distance)


def lerp(a, b, weight):
    return add(a, mul(sub(b, a), weight))


def smooth(t):
    t = min(1.0, max(0.0, t))
    return t * t * (3.0 - 2.0 * t)


def matrix(head, tail):
    y = unit(sub(tail, head))
    reference = (1.0, 0.0, 0.0) if abs(y[0]) < 0.95 else (0.0, 0.0, 1.0)
    x = unit(sub(reference, mul(y, dot(reference, y))))
    z = cross(x, y)
    return [[x[i], y[i], z[i], head[i]] for i in range(3)] + [[0.0, 0.0, 0.0, 1.0]]


def matmul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(4)) for j in range(4)] for i in range(4)]


def inverse(a):
    result = [[a[j][i] for j in range(3)] + [-sum(a[j][i] * a[j][3] for j in range(3))] for i in range(3)]
    return result + [[0.0, 0.0, 0.0, 1.0]]


def vector(a, v):
    return tuple(sum(a[i][j] * v[j] for j in range(3)) for i in range(3))


def quaternion(a):
    trace = sum(a[i][i] for i in range(3))
    if trace > 0.0:
        s = math.sqrt(trace + 1.0) * 2.0
        q = ((a[2][1] - a[1][2]) / s, (a[0][2] - a[2][0]) / s, (a[1][0] - a[0][1]) / s, s / 4.0)
    else:
        i = max(range(3), key=lambda axis: a[axis][axis])
        j, k = (i + 1) % 3, (i + 2) % 3
        s = math.sqrt(max(0.0, 1.0 + a[i][i] - a[j][j] - a[k][k])) * 2.0
        values = [0.0] * 4
        values[i] = s / 4.0
        values[j] = (a[j][i] + a[i][j]) / s
        values[k] = (a[k][i] + a[i][k]) / s
        values[3] = (a[k][j] - a[j][k]) / s
        q = tuple(values)
    return mul(q, 1.0 / length(q))


def rotation(pitch, roll=0.0):
    cp, sp, cr, sr = math.cos(pitch), math.sin(pitch), math.cos(roll), math.sin(roll)
    return [[cr, -sr * cp, sr * sp, 0.0], [sr, cr * cp, -cr * sp, 0.0], [0.0, sp, cp, 0.0], [0.0, 0.0, 0.0, 1.0]]


# Coordinates are meters, Y up, -Z forward, after baking the old BodyMesh yaw.
# Joint placement follows the existing 2.29m mesh, including its long right arm.
SPECS = [
    ("hips", None, (-0.04, 0.95, 0.18), (-0.04, 1.25, 0.16)),
    ("spine", "hips", (-0.04, 1.25, 0.16), (-0.03, 1.60, 0.11)),
    ("chest", "spine", (-0.03, 1.60, 0.11), (-0.14, 1.97, -0.06)),
    ("head", "chest", (-0.14, 1.97, -0.06), (-0.16, 2.23, -0.25)),
    ("upper_arm_r", "chest", (0.39, 1.69, 0.21), (0.46, 1.02, -0.30)),
    ("forearm_r", "upper_arm_r", (0.46, 1.02, -0.30), (0.36, 0.31, -0.87)),
    ("hand_r", "forearm_r", (0.36, 0.31, -0.87), (0.36, 0.12, -1.13)),
    ("upper_arm_l", "chest", (-0.43, 1.62, 0.29), (-0.59, 1.06, 0.28)),
    ("forearm_l", "upper_arm_l", (-0.59, 1.06, 0.28), (-0.58, 0.64, 0.38)),
    ("hand_l", "forearm_l", (-0.58, 0.64, 0.38), (-0.57, 0.41, 0.40)),
    ("thigh_r", "hips", (0.23, 0.94, 0.18), (0.30, 0.53, -0.08)),
    ("shin_r", "thigh_r", (0.30, 0.53, -0.08), (0.30, 0.14, 0.26)),
    ("foot_r", "shin_r", (0.30, 0.14, 0.26), (0.30, 0.075, -0.17)),
    ("thigh_l", "hips", (-0.29, 0.94, 0.19), (-0.35, 0.53, -0.07)),
    ("shin_l", "thigh_l", (-0.35, 0.53, -0.07), (-0.35, 0.14, 0.27)),
    ("foot_l", "shin_l", (-0.35, 0.14, 0.27), (-0.35, 0.075, -0.15)),
]
NAMES = [spec[0] for spec in SPECS]
PARENTS = {name: parent for name, parent, _, _ in SPECS}
HEADS = {name: head for name, _, head, _ in SPECS}
TAILS = {name: tail for name, _, _, tail in SPECS}
REST = {name: matrix(head, tail) for name, _, head, tail in SPECS}


def solve_joint(origin, end, middle_rest, first_length, second_length):
    axis = sub(end, origin)
    distance = length(axis)
    direction = unit(axis)
    limited = min(first_length + second_length - 1e-5, max(abs(first_length - second_length) + 1e-5, distance))
    end = add(origin, mul(direction, limited))
    reach = (first_length * first_length - second_length * second_length + limited * limited) / (2.0 * limited)
    height = math.sqrt(max(0.0, first_length * first_length - reach * reach))
    bend = sub(middle_rest, mul(direction, dot(middle_rest, direction)))
    if length(bend) < 1e-6:
        bend = sub((0.0, 0.0, -1.0), mul(direction, -direction[2]))
    return add(add(origin, mul(direction, reach)), mul(unit(bend), height)), end


def limb_pose(result, first, second, last, origin, end, last_rotation=None):
    first_length = length(sub(TAILS[first], HEADS[first]))
    second_length = length(sub(TAILS[second], HEADS[second]))
    rest_axis = unit(sub(HEADS[last], HEADS[first]))
    rest_middle = sub(HEADS[second], HEADS[first])
    bend = sub(rest_middle, mul(rest_axis, dot(rest_middle, rest_axis)))
    middle, end = solve_joint(origin, end, bend, first_length, second_length)
    result[first] = matrix(origin, middle)
    result[second] = matrix(middle, end)
    if last_rotation is None:
        delta = matmul(result[second], inverse(REST[second]))
        last_rotation = matmul(delta, REST[last])
    last_rotation = [row[:] for row in last_rotation]
    for axis in range(3):
        last_rotation[axis][3] = end[axis]
    result[last] = last_rotation


def smooth_skin_weights(positions, indices, joints, weights):
    # The nearest-three seed jumps when two similarly distant joints swap rank.
    # Diffuse on the original surface, keeping planted soles and distal claws
    # anchored. Neither topology nor UV seams are changed by weight smoothing.
    neighbors = [dict() for _ in positions]
    for triangle in range(0, len(indices), 3):
        vertices = [indices[triangle + edge][0] for edge in range(3)]
        for edge in range(3):
            first, second = vertices[edge], vertices[(edge + 1) % 3]
            if first == second:
                continue
            influence = 1.0 / max(length(sub(positions[first], positions[second])), 0.01)
            neighbors[first][second] = influence
            neighbors[second][first] = influence
    fields = [[0.0] * len(SPECS) for _ in positions]
    for index, (bound_joints, bound_weights) in enumerate(zip(joints, weights)):
        for joint, weight in zip(bound_joints, bound_weights):
            fields[index][joint] += weight
    pinned = [
        (point[1] < 0.10 and point[2] > -0.32)
        or (point[1] < 0.25 and point[2] < -0.40)
        for point in positions
    ]
    for _ in range(100):
        following = []
        for index, links in enumerate(neighbors):
            if pinned[index] or not links:
                following.append(fields[index])
                continue
            total = sum(links.values())
            field = [value * 0.5 for value in fields[index]]
            for neighbor, influence in links.items():
                factor = influence * 0.5 / total
                for joint, value in enumerate(fields[neighbor]):
                    field[joint] += value * factor
            following.append(field)
        fields = following
    result_joints, result_weights = [], []
    for field in fields:
        ranked = sorted(range(len(SPECS)), key=lambda joint: field[joint], reverse=True)
        # Make the fourth influence fade continuously to zero at the fifth.
        # Truncating a nonzero weight would introduce another surface tear.
        threshold = field[ranked[4]]
        selected = ranked[:4]
        factors = [max(0.0, field[joint] - threshold) for joint in selected]
        total = sum(factors)
        if total <= 1e-12:
            factors = [field[joint] for joint in selected]
            total = sum(factors)
        if total <= 1e-12:
            raise ValueError("unbound vertex after smoothing")
        result_joints.append(tuple(selected))
        result_weights.append(tuple(value / total for value in factors))
    return result_joints, result_weights


def pose(clip, time, speed, windup, recover, cycle):
    phase = time / cycle if clip == "walk" else 0.0
    pelvis = HEADS["hips"]
    pitch, roll = 0.0, 0.0
    if clip == "walk":
        pelvis = add(pelvis, (0.008 * math.sin(2.0 * math.pi * phase), -0.025 * (1.0 - math.cos(4.0 * math.pi * phase)), 0.0))
        pitch, roll = -0.025 + 0.014 * math.sin(2.0 * math.pi * phase), 0.012 * math.sin(2.0 * math.pi * phase)
    elif clip == "idle":
        pelvis = add(pelvis, (0.0, 0.005 * math.sin(math.pi * time), 0.0))
        pitch = 0.006 * math.sin(math.pi * time)
    elif clip == "attack":
        if time < windup * 0.72:
            anticipation = smooth(time / (windup * 0.72))
            pitch = 0.045 * anticipation
        elif time < windup:
            strike = smooth((time - windup * 0.72) / (windup * 0.28))
            pitch = 0.045 - 0.165 * strike
            pelvis = add(pelvis, (0.0, -0.04 * strike, 0.0))
        else:
            settled = 1.0 - smooth((time - windup) / recover)
            pitch = -0.12 * settled
            pelvis = add(pelvis, (0.0, -0.04 * settled, 0.0))
    elif clip == "death":
        amount = smooth(time / 2.4)
        # Lay the actual hip-to-head axis back onto the ground. Falling forward
        # puts the long projecting claw below the torso and props the corpse up.
        pitch = 1.831 * amount
        pelvis = add(pelvis, (0.0, -0.50 * amount, 0.0))
    turn = rotation(pitch, roll)

    def body(point):
        return add(pelvis, vector(turn, sub(point, HEADS["hips"])))

    if clip == "death":
        # Keep the connected trunk and legs together. Fold the entire right arm
        # chain at its shoulder so the long claw settles beside the prone body.
        collapse = [row[:] for row in turn]
        translation = sub(pelvis, vector(turn, HEADS["hips"]))
        for axis in range(3):
            collapse[axis][3] = translation[axis]
        fold = rotation(-0.665 * amount)
        shoulder = HEADS["upper_arm_r"]
        shoulder_translation = sub(shoulder, vector(fold, shoulder))
        for axis in range(3):
            fold[axis][3] = shoulder_translation[axis]
        arm = matmul(collapse, fold)
        return {name: matmul(arm if name in ["upper_arm_r", "forearm_r", "hand_r"] else collapse, REST[name]) for name in NAMES}

    result = {name: matrix(body(HEADS[name]), body(TAILS[name])) for name in ["hips", "spine", "chest", "head"]}
    for side, offset in [("r", 0.0), ("l", 0.5)]:
        foot_name, thigh_name = "foot_" + side, "thigh_" + side
        ankle = HEADS[foot_name]
        if clip == "walk":
            p = (phase + offset) % 1.0
            stance = 0.55
            stroke = speed * cycle * stance
            if p <= stance:
                ankle = (ankle[0], ankle[1], HEADS["hips"][2] - stroke * 0.5 + speed * cycle * p)
            else:
                swing = (p - stance) / (1.0 - stance)
                ankle = (ankle[0], ankle[1] + 0.14 * math.sin(math.pi * swing), HEADS["hips"][2] + stroke * (0.5 - smooth(swing)))
        elif clip == "death":
            ankle = body(ankle)
        limb_pose(result, thigh_name, "shin_" + side, foot_name, body(HEADS[thigh_name]), ankle, REST[foot_name])
        hand_name = "hand_" + side
        wrist = body(HEADS[hand_name])
        if clip == "walk":
            clearance = 0.15 if side == "r" else 0.0
            wrist = add(wrist, (0.0, clearance + 0.02 * math.sin(2.0 * math.pi * (phase + offset)), 0.09 * math.sin(2.0 * math.pi * (phase + offset))))
        elif clip == "attack" and side == "r":
            raised = (0.38, 2.25, -0.55)
            impact = (0.36, 0.35, -0.92)
            apex = windup * 0.72
            if time < apex:
                wrist = lerp(HEADS[hand_name], raised, smooth(time / apex))
            elif time < windup:
                wrist = lerp(raised, impact, smooth((time - apex) / (windup - apex)))
            else:
                wrist = lerp(impact, HEADS[hand_name], smooth((time - windup) / recover))
        limb_pose(result, "upper_arm_" + side, "forearm_" + side, hand_name, body(HEADS["upper_arm_" + side]), wrist)
    return result


def main():
    source, output = map(Path, sys.argv[1:3])
    source_bytes = source.read_bytes()
    json_length, json_type = struct.unpack_from("<II", source_bytes, 12)
    if json_type != 0x4E4F534A:
        raise ValueError("expected GLB JSON chunk")
    document = json.loads(source_bytes[20:20 + json_length])
    bin_header = 20 + json_length
    bin_length, bin_type = struct.unpack_from("<II", source_bytes, bin_header)
    if bin_type != 0x004E4942:
        raise ValueError("expected GLB binary chunk")
    binary = bytearray(source_bytes[bin_header + 8:bin_header + 8 + bin_length])
    if len(document["meshes"]) != 1 or len(document["meshes"][0]["primitives"]) != 1:
        raise ValueError("expected the existing single hulking primitive")

    def read_accessor(index):
        accessor = document["accessors"][index]
        view = document["bufferViews"][accessor["bufferView"]]
        counts = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}
        formats = {5121: "B", 5123: "H", 5125: "I", 5126: "f"}
        fmt = "<" + formats[accessor["componentType"]] * counts[accessor["type"]]
        stride = view.get("byteStride", struct.calcsize(fmt))
        offset = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
        return [struct.unpack_from(fmt, binary, offset + i * stride) for i in range(accessor["count"])]

    def append_accessor(values, kind, component=5126, bounds=False):
        counts = {"SCALAR": 1, "VEC3": 3, "VEC4": 4, "MAT4": 16}
        while len(binary) % 4:
            binary.append(0)
        offset = len(binary)
        flat = [value for row in values for value in row]
        binary.extend(struct.pack("<" + ("f" if component == 5126 else "H") * len(flat), *flat))
        view = len(document["bufferViews"])
        document["bufferViews"].append({"buffer": 0, "byteOffset": offset, "byteLength": len(binary) - offset})
        accessor = {"bufferView": view, "componentType": component, "count": len(values), "type": kind}
        if bounds:
            accessor["min"] = [min(row[i] for row in values) for i in range(counts[kind])]
            accessor["max"] = [max(row[i] for row in values) for i in range(counts[kind])]
        index = len(document["accessors"])
        document["accessors"].append(accessor)
        return index

    primitive = document["meshes"][0]["primitives"][0]
    source_positions = read_accessor(primitive["attributes"]["POSITION"])
    floor_shift = -min(vertex[1] for vertex in source_positions)
    positions = [(-z, y + floor_shift, x) for x, y, z in source_positions]
    normals = [(-z, y, x) for x, y, z in read_accessor(primitive["attributes"]["NORMAL"])]
    joints, weights = [], []
    for point in positions:
        distances = []
        for index, (_, _, head, tail) in enumerate(SPECS):
            segment = sub(tail, head)
            progress = min(1.0, max(0.0, dot(sub(point, head), segment) / dot(segment, segment)))
            distances.append((length(sub(point, add(head, mul(segment, progress)))), index))
        # Sole skin below the ankle belongs to its foot, not the nearby shin.
        # Otherwise shin rotation folds a planted heel through the floor.
        ankle_y = min(HEADS["foot_l"][1], HEADS["foot_r"][1])
        foot_front = min(TAILS["foot_l"][2], TAILS["foot_r"][2]) - 0.15
        claw_back = foot_front
        if point[1] <= HEADS["hand_r"][1] + 0.20 and point[2] < claw_back:
            # Keep the full low projecting claw together, including its rear
            # fingertips; the previous midpoint cut through connected faces.
            arm_indices = [NAMES.index(name) for name in ["upper_arm_r", "forearm_r", "hand_r"]]
            closest = sorted(distance for distance in distances if distance[1] in arm_indices)
        elif point[1] <= ankle_y and point[2] > foot_front:
            foot = min(["foot_l", "foot_r"], key=lambda name: abs(point[0] - HEADS[name][0]))
            closest = [distances[NAMES.index(foot)]]
        else:
            closest = sorted(distances)[:3]
        factors = [1.0 / max(distance, 0.015) ** 4 for distance, _ in closest]
        total = sum(factors)
        joints.append(tuple(index for _, index in closest) + (0,) * (4 - len(closest)))
        weights.append(tuple(value / total for value in factors) + (0.0,) * (4 - len(closest)))
    joints, weights = smooth_skin_weights(positions, read_accessor(primitive["indices"]), joints, weights)
    primitive["attributes"]["POSITION"] = append_accessor(positions, "VEC3", bounds=True)
    primitive["attributes"]["NORMAL"] = append_accessor(normals, "VEC3")
    primitive["attributes"]["JOINTS_0"] = append_accessor(joints, "VEC4", 5123)
    primitive["attributes"]["WEIGHTS_0"] = append_accessor(weights, "VEC4")

    nodes = []
    for name in NAMES:
        parent = PARENTS[name]
        local = matmul(inverse(REST[parent]), REST[name]) if parent else REST[name]
        node = {"name": name, "translation": [local[i][3] for i in range(3)], "rotation": quaternion(local)}
        children = [NAMES.index(child) for child in NAMES if PARENTS[child] == name]
        if children:
            node["children"] = children
        nodes.append(node)
    nodes.append({"name": "HulkingMesh", "mesh": 0, "skin": 0})
    nodes.append({"name": "HulkingRig", "children": [len(SPECS), 0]})
    document["nodes"] = nodes
    document["scenes"] = [{"name": "HulkingHostRepaired", "nodes": [len(SPECS) + 1]}]
    document["scene"] = 0
    bind_values = [tuple(inverse(REST[name])[row][col] for col in range(4) for row in range(4)) for name in NAMES]
    document["skins"] = [{"name": "HulkingRig", "skeleton": 0, "joints": list(range(len(SPECS))), "inverseBindMatrices": append_accessor(bind_values, "MAT4")}]

    repo = source.resolve().parents[4]
    config_source = (repo / "godot/autoload/game_config.gd").read_text(encoding="utf-8-sig")
    def config_number(name):
        match = re.search(r"const " + re.escape(name) + r": float = ([0-9.]+)", config_source)
        if match is None:
            raise ValueError("missing frozen numeric contract: " + name)
        return float(match.group(1))
    speed = config_number("HULKING_HOST_SPEED")
    windup = config_number("HULKING_HOST_WINDUP")
    recover = config_number("HULKING_HOST_RECOVER")
    cycle = 1.0  # Existing big-stride Animation uses Godot's default 1s length.
    durations = {"idle": 2.0, "walk": cycle, "attack": windup + recover, "death": 2.4}
    document["animations"] = []
    for clip, duration in durations.items():
        frame_count = max(2, int(math.ceil(duration * 60.0)) + 1)
        times = [duration * frame / (frame_count - 1) for frame in range(frame_count)]
        input_accessor = append_accessor([(time,) for time in times], "SCALAR", bounds=True)
        frames = [pose(clip, time, speed, windup, recover, cycle) for time in times]
        if clip == "death":
            for frame in frames:
                skin_frames = [matmul(frame[name], inverse(REST[name])) for name in NAMES]
                # The shoulder folds independently of the trunk, so contact
                # must use every vertex's real four-influence skinning result.
                bottom = min(sum((dot(skin_frames[joint][1][:3], point) + skin_frames[joint][1][3]) * weight
                                 for joint, weight in zip(bound_joints, bound_weights) if weight > 0.0)
                             for point, bound_joints, bound_weights in zip(positions, joints, weights))
                if bottom < 0.0:
                    for bone in frame.values():
                        bone[1][3] -= bottom
        animation = {"name": clip, "samplers": [], "channels": []}
        for index, name in enumerate(NAMES):
            translations, rotations = [], []
            for frame in frames:
                parent = PARENTS[name]
                local = matmul(inverse(frame[parent]), frame[name]) if parent else frame[name]
                translations.append(tuple(local[i][3] for i in range(3)))
                q = quaternion(local)
                if rotations and dot(rotations[-1], q) < 0.0:
                    q = mul(q, -1.0)
                rotations.append(q)
            for path, values, kind in [("translation", translations, "VEC3"), ("rotation", rotations, "VEC4")]:
                sampler = len(animation["samplers"])
                animation["samplers"].append({"input": input_accessor, "output": append_accessor(values, kind), "interpolation": "LINEAR"})
                animation["channels"].append({"sampler": sampler, "target": {"node": index, "path": path}})
        document["animations"].append(animation)
    source_hash = hashlib.sha256(source_bytes).hexdigest()
    notes = {"source_sha256": source_hash, "source": source.name, "forward": [0, 0, -1], "yaw_baked": -math.pi / 2.0, "floor_shift": floor_shift, "bone_count": len(SPECS), "speed": speed, "windup": windup, "recover": recover, "uv_indices_materials_images": "unchanged", "weight_method": "existing nearest-three-segment inverse-distance^4 seeds; original-surface smoothing with sole/claw anchors; continuous four-influence compression", "weight_smoothing_iterations": 100, "death": "connected backward collapse, right-shoulder fold, actual complete weighted mesh floor contact at every key", "death_back_pitch": 1.831, "death_shoulder_fold": 0.665}
    document["asset"]["extras"] = {"hulking_repair": notes}
    document["buffers"][0]["byteLength"] = len(binary)
    json_bytes = json.dumps(document, separators=(",", ":")).encode("utf-8")
    while len(json_bytes) % 4:
        json_bytes += b" "
    while len(binary) % 4:
        binary.append(0)
    result = struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(json_bytes) + 8 + len(binary))
    result += struct.pack("<II", len(json_bytes), 0x4E4F534A) + json_bytes
    result += struct.pack("<II", len(binary), 0x004E4942) + binary
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(result)
    notes.update({"output": output.name, "output_sha256": hashlib.sha256(result).hexdigest(), "vertices": len(positions), "triangles": len(read_accessor(primitive["indices"])) // 3, "clips": durations, "joints": {name: {"parent": parent, "head": head, "tail": tail} for name, parent, head, tail in SPECS}})
    report_path = output.parent / (output.stem + "_report.json")
    report_path.write_text(json.dumps(notes, ensure_ascii=False, indent=2), encoding="utf-8")
    print("HULKING_REPAIR", json.dumps(notes, ensure_ascii=False))


if __name__ == "__main__":
    main()
