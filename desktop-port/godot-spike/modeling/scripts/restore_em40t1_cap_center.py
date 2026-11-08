"""Recover the authentic center patch of the existing 184-face transplanted ring.

Source: godot/assets/models/weapons/em57s2_viewmodel.glb. All 184 faces of
modeling/em-weapons/em57s2/tail_parts/tail_11.glb exactly match this identity
GLB in glTF space. The historical name tail_11 is misleading: it lies at the
negative-Z end, where em57s2.tscn places Muzzle. It is not the gun's rear cap.

The source center is a separate 34-face surface with a 36-edge boundary, only
about 0.011 m behind this same ring. The ring was originally open; its native
center and ring do not share boundary edges. Recover the finite authentic
surface, then close that existing local gap without extrapolating a plane.

Transplant map: x'=(x-cx)*scale, y'=(y-cy)*scale+.19,
z'=(z-source_min_z)*scale-.08, scale=.115/max(source_xy_extent).
This is the exact map used by move_em57s2_actual_tail.py after Blender's
glTF (x,y,z) -> (x,-z,y) conversion. The player's side of EM40T1 is +Z.
To preserve the native recessed depth when reversing that viewing direction,
reflect only the recovered patch Z about the actual 34-edge opening's mean Z.
For this reflection, normals become (Nx,Ny,-Nz), and winding is reversed.
The original 184 faces, UVs, materials, existing ring shape remain untouched.
"""
import copy
import json
import math
import os
import sys
from collections import Counter, defaultdict

from restore_optic_shells import append_accessor, read_glb, split_polygon, triangle_area, write_glb
from restore_em40t1_shell import triangles, triangle_key


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def barycentric_xy(point, face):
    a, b, c = [vertex["POSITION"] for vertex in face]
    u, v, w = (b[0] - a[0], b[1] - a[1]), (c[0] - a[0], c[1] - a[1]), (point[0] - a[0], point[1] - a[1])
    determinant = u[0] * v[1] - u[1] * v[0]
    if abs(determinant) < 1e-16:
        return None
    beta = (w[0] * v[1] - w[1] * v[0]) / determinant
    gamma = (u[0] * w[1] - u[1] * w[0]) / determinant
    return 1.0 - beta - gamma, beta, gamma


def boundary_loops(vertices):
    edges = Counter()
    values = {}
    for start in range(0, len(vertices), 3):
        face = vertices[start:start + 3]
        keys = [tuple(round(value, 6) for value in vertex["POSITION"]) for vertex in face]
        values.update(zip(keys, face))
        for edge in range(3):
            edges[tuple(sorted((keys[edge], keys[(edge + 1) % 3])))] += 1
    graph = defaultdict(set)
    for (a, b), count in edges.items():
        if count == 1:
            graph[a].add(b)
            graph[b].add(a)
    loops = []
    visited = set()
    for start in sorted(graph):
        if start in visited or len(graph[start]) != 2:
            continue
        loop, previous, current = [], None, start
        while current not in loop and len(graph[current]) == 2:
            loop.append(current)
            following = next(value for value in sorted(graph[current]) if value != previous)
            previous, current = current, following
        visited.update(loop)
        if current == start:
            loops.append([values[key] for key in loop])
    return loops


def triangulate_loop(loop):
    indices = list(range(len(loop)))
    positions = [vertex["POSITION"] for vertex in loop]
    area = sum(positions[a][0] * positions[b][1] - positions[b][0] * positions[a][1]
               for a, b in zip(indices, indices[1:] + indices[:1]))
    if area < 0.0:
        indices.reverse()
    result = []
    while len(indices) > 3:
        for index, current in enumerate(indices):
            ear = [indices[index - 1], current, indices[(index + 1) % len(indices)]]
            a, b, c = [positions[value] for value in ear]
            if (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]) <= 1e-12:
                continue
            face = [loop[value] for value in ear]
            if any((weights := barycentric_xy(positions[value], face)) is not None
                   and min(weights) > 1e-8 for value in indices if value not in ear):
                continue
            result.append(face)
            del indices[index]
            break
        else:
            raise RuntimeError("native opening could not be triangulated")
    result.append([loop[value] for value in indices])
    return result


def bridge_loops(outer, inner, center=(0.0, 0.19)):
    """Zip two star-shaped native boundaries without moving their vertices."""
    def ordered(loop):
        values = [(math.atan2(v['POSITION'][1]-center[1], v['POSITION'][0]-center[0]), v) for v in loop]
        values.sort(key=lambda value: value[0])
        return [(angle, vertex) for angle, vertex in values] + [(values[0][0] + 2*math.pi, values[0][1])]

    a, b = ordered(outer), ordered(inner)
    ia = ib = 0
    result = []
    while ia < len(outer) or ib < len(inner):
        if ib == len(inner) or (ia < len(outer) and a[ia+1][0] <= b[ib+1][0]):
            result.append([a[ia][1], a[ia+1][1], b[ib][1]])
            ia += 1
        else:
            result.append([a[ia][1], b[ib+1][1], b[ib][1]])
            ib += 1
    return result


def edge_counts(vertices, precision=6):
    counts = Counter()
    for start in range(0, len(vertices), 3):
        keys = [tuple(round(v, precision) for v in vertex['POSITION']) for vertex in vertices[start:start+3]]
        for a, b in zip(keys, keys[1:]+keys[:1]):
            counts[tuple(sorted((a,b)))] += 1
    return counts


def main(current, source, tail_source, output):
    document, binary = read_glb(current)
    if len(document['meshes'][0]['primitives']) != 3:
        raise RuntimeError('expected original shell, original ring, restored shell; do not add the center twice')
    ring_primitive = document["meshes"][0]["primitives"][1]
    ring_vertices = triangles(document, binary, ring_primitive)
    if len(ring_vertices) != 184 * 3:
        raise RuntimeError("the original 184-face ring is required")
    opening = next(loop for loop in boundary_loops(ring_vertices) if len(loop) == 34)
    opening_plane_z = sum(vertex['POSITION'][2] for vertex in opening)/len(opening)
    source_document, source_binary = read_glb(source)
    native = source_document["meshes"][0]["primitives"][0]
    native_vertices = triangles(source_document, source_binary, native)
    tail_document, tail_binary = read_glb(tail_source)
    tail_vertices = triangles(tail_document, tail_binary, tail_document["meshes"][0]["primitives"][0])
    positions = [vertex["POSITION"] for vertex in tail_vertices]
    lo = [min(point[axis] for point in positions) for axis in range(3)]
    hi = [max(point[axis] for point in positions) for axis in range(3)]
    scale = 0.115 / max(hi[0] - lo[0], hi[1] - lo[1])
    cx, cy = (lo[0] + hi[0]) * 0.5, (lo[1] + hi[1]) * 0.5
    def transformed(vertex):
        result = copy.deepcopy(vertex)
        x,y,z = result['POSITION']
        result['POSITION'] = ((x-cx)*scale, (y-cy)*scale+.19, (z-lo[2])*scale-.08)
        return result

    faces = [native_vertices[start:start+3] for start in range(0, len(native_vertices), 3)]
    native_keys = {triangle_key(face) for face in faces}
    tail_keys = {triangle_key(tail_vertices[i:i+3]) for i in range(0,len(tail_vertices),3)}
    if not tail_keys <= native_keys or len(tail_keys) != 184:
        raise RuntimeError('the transplanted ring is not geometrically identical to the source')
    mapped_keys = {triangle_key([transformed(v) for v in tail_vertices[i:i+3]]) for i in range(0,len(tail_vertices),3)}
    ring_keys = {triangle_key(ring_vertices[i:i+3]) for i in range(0,len(ring_vertices),3)}
    if mapped_keys != ring_keys:
        raise RuntimeError('the documented transplant map does not reproduce the current ring')

    nearby = [(i, face) for i, face in enumerate(faces)
              if triangle_key(face) not in tail_keys
              and min(v['POSITION'][2] for v in face) < hi[2]+.02
              and max(v['POSITION'][2] for v in face) > lo[2]-.01]
    candidates = []
    for index, face in nearby:
        weights = barycentric_xy((cx, cy), face)
        if weights is not None and min(weights) >= 0.0:
            candidates.append((sum(weight*vertex['POSITION'][2] for weight,vertex in zip(weights,face)), index))
    center_z, seed = min(candidates, key=lambda value:value[0])
    outer_face = faces[seed]
    a, b, c = [vertex["POSITION"] for vertex in outer_face]
    normal = cross(tuple(b[axis] - a[axis] for axis in range(3)), tuple(c[axis] - a[axis] for axis in range(3)))
    normal_length = math.sqrt(dot(normal, normal))
    normal = tuple(value / normal_length for value in normal)
    if normal[2] >= -0.95:
        raise RuntimeError('the source center does not face the native negative-Z opening')
    edges = defaultdict(list)
    for index, face in nearby:
        keys = [tuple(round(x,7) for x in v['POSITION']) for v in face]
        for a,b in zip(keys,keys[1:]+keys[:1]):
            edges[tuple(sorted((a,b)))].append(index)
    graph = defaultdict(set)
    for indices_for_edge in edges.values():
        for index in indices_for_edge:
            graph[index].update(indices_for_edge)
    component, queue = {seed}, [seed]
    while queue:
        index = queue.pop()
        for neighbor in graph[index]-component:
            component.add(neighbor)
            queue.append(neighbor)
    if len(component) != 34:
        raise RuntimeError(f'expected the authentic 34-face center patch, found {len(component)}')
    transformed_faces = [[transformed(v) for v in faces[index]] for index in sorted(component)]
    for face in transformed_faces:
        for vertex in face:
            x,y,z=vertex['POSITION']
            vertex['POSITION']=(x,y,2*opening_plane_z-z)
    loops = boundary_loops([v for face in transformed_faces for v in face])
    if len(loops) != 1 or len(loops[0]) != 36:
        raise RuntimeError('the authentic center does not have its expected 36-edge native outline')
    inner = loops[0]
    attributes = {name: [] for name in native["attributes"]}
    indices = []
    added_vertices = []

    def append_triangle(face):
        if triangle_area(face) < 1e-15:
            return
        added_vertices.extend(face)
        for vertex in face:
            indices.append((len(attributes["POSITION"]),))
            for name in attributes:
                attributes[name].append(vertex[name])

    for face in transformed_faces:
        face = copy.deepcopy(face[::-1])
        for vertex in face:
            x,y,z=vertex['NORMAL']
            vertex['NORMAL']=(x,y,-z)
            if 'TANGENT' in vertex:
                x,y,z,w = vertex['TANGENT']
                vertex['TANGENT'] = x,y,-z,-w
        append_triangle(face)
    center_triangles = len(indices) // 3
    for face in bridge_loops(opening, inner):
        face = copy.deepcopy(face)
        a,b,c = [v['POSITION'] for v in face]
        n = cross(tuple(b[k]-a[k] for k in range(3)),tuple(c[k]-a[k] for k in range(3)))
        if n[2] < 0:
            face.reverse()
            n = tuple(-value for value in n)
        length = math.sqrt(dot(n,n))
        for vertex in face:
            vertex['NORMAL'] = tuple(value/length for value in n)
        append_triangle(face)
    if center_triangles < 2:
        raise RuntimeError("no authentic center was recovered")
    counts = edge_counts(ring_vertices+added_vertices)
    closed_edges = []
    for loop in [opening,inner]:
        for a,b in zip(loop,loop[1:]+loop[:1]):
            key = tuple(sorted(tuple(round(v,6) for v in point['POSITION']) for point in [a,b]))
            closed_edges.append(counts[key])
    if any(count != 2 for count in closed_edges):
        raise RuntimeError('center/native-ring local boundary was not closed exactly')
    primitive = copy.deepcopy(native)
    primitive["attributes"] = {name: append_accessor(document, binary, values,
                               source_document["accessors"][native["attributes"][name]]["type"])
                              for name, values in attributes.items()}
    primitive["indices"] = append_accessor(document, binary, indices, "SCALAR", 5125)
    primitive["material"] = ring_primitive["material"]
    document["meshes"][0]["primitives"].append(primitive)
    write_glb(output, document, binary)
    print(json.dumps({"original_ring_faces_retained": 184, "source_path": source,
                      "exact_source_ring_matches": len(tail_keys), 'transplant_ring_matches':len(mapped_keys),
                      'source_face_indices':sorted(component),'authentic_center_faces':len(component),
                      "opening_edges": len(opening), "recovered_center_triangles": center_triangles,
                      "opening_connection_triangles": len(indices) // 3 - center_triangles,
                      "source_center_seed_normal": normal, "source_center_seed_z": center_z,
                      'player_facing_direction':'+Z', 'depth_reflection_plane_z':opening_plane_z,
                      'recovered_patch_z_range':[min(v['POSITION'][2] for face in transformed_faces for v in face),
                                                 max(v['POSITION'][2] for face in transformed_faces for v in face)],
                      'closed_native_outline_edges':len(closed_edges),
                      "output_bytes": os.path.getsize(output)}, indent=2))


if __name__ == "__main__":
    if len(sys.argv) != 5:
        raise SystemExit("usage: restore_em40t1_cap_center.py <current.glb> <smg.glb> <tail_11.glb> <output.glb>")
    main(*map(os.path.abspath, sys.argv[1:]))
