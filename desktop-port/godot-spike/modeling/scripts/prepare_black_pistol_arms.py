"""Keep the downloaded DJMaesen rig intact and cut its documented action ranges.

Run with Blender --background --python-exit-code 1 --python this_file.
Only Python's standard library is used; the source GLB is never changed.
The mesh, skin weights, inverse binds and joint transforms are copied exactly.
"""
import copy
import hashlib
import json
import math
import struct
from pathlib import Path

ROOT = Path.cwd()
SOURCE = ROOT / 'godot/raw_assets/community_weapons/g17_pistol_-_animated.glb'
DESTINATION = ROOT / 'godot/addons/community_weapons/black_pistol_arms.glb'
REPORT = ROOT / 'desktop-port/godot-spike/modeling/community_weapons/black_pistol_arms.json'
# DJMaesen's published keyframes, at the source 30 fps, not Blender's import fps.
RANGES = {'fire': (0, 11), 'reload': (12, 82), 'fire_last': (83, 94),
          'reload_empty': (95, 175), 'hide': (176, 187),
          'ready': (187, 233), 'idle': (234, 264)}


blob = SOURCE.read_bytes()
json_length, json_type = struct.unpack_from('<II', blob, 12)
if json_type != 0x4e4f534a:
    raise RuntimeError('Expected embedded glTF JSON')
doc = json.loads(blob[20:20 + json_length])
binary_length, binary_type = struct.unpack_from('<II', blob, 20 + json_length)
if binary_type != 0x004e4942:
    raise RuntimeError('Expected embedded glTF binary')
binary = bytearray(blob[28 + json_length:28 + json_length + binary_length])
original_skin = copy.deepcopy(doc['skins'])
original_nodes = copy.deepcopy(doc['nodes'])
if len(original_skin) != 1 or len(original_skin[0]['joints']) != 60:
    raise RuntimeError('Expected the native sixty-joint skeleton')


def read_accessor(index):
    accessor = doc['accessors'][index]
    if accessor['componentType'] != 5126 or 'sparse' in accessor:
        raise RuntimeError('Expected dense float animation accessor')
    width = {'SCALAR': 1, 'VEC3': 3, 'VEC4': 4}[accessor['type']]
    view = doc['bufferViews'][accessor['bufferView']]
    start = view.get('byteOffset', 0) + accessor.get('byteOffset', 0)
    stride = view.get('byteStride', width * 4)
    return [struct.unpack_from('<' + 'f' * width, binary, start + i * stride)
            for i in range(accessor['count'])]


def append_accessor(values, kind):
    while len(binary) % 4:
        binary.append(0)
    offset = len(binary)
    width = len(values[0])
    for value in values:
        binary.extend(struct.pack('<' + 'f' * width, *value))
    view_index = len(doc['bufferViews'])
    doc['bufferViews'].append({'buffer': 0, 'byteOffset': offset, 'byteLength': len(values) * width * 4})
    accessor = {'bufferView': view_index, 'componentType': 5126, 'count': len(values), 'type': kind}
    if kind == 'SCALAR':
        accessor['min'] = [min(v[0] for v in values)]
        accessor['max'] = [max(v[0] for v in values)]
    index = len(doc['accessors'])
    doc['accessors'].append(accessor)
    return index


def interpolate(times, values, time, rotation):
    if time <= times[0]:
        return values[0]
    if time >= times[-1]:
        return values[-1]
    right = next(i for i, t in enumerate(times) if t >= time)
    left = right - 1
    weight = (time - times[left]) / (times[right] - times[left])
    a, b = values[left], values[right]
    if rotation:
        dot = sum(x * y for x, y in zip(a, b))
        if dot < 0:
            b = tuple(-x for x in b)
            dot = -dot
        if dot < 0.9995:
            angle = math.acos(min(1.0, dot))
            aw = math.sin((1 - weight) * angle) / math.sin(angle)
            bw = math.sin(weight * angle) / math.sin(angle)
            return tuple(aw * x + bw * y for x, y in zip(a, b))
    result = tuple((1 - weight) * x + weight * y for x, y in zip(a, b))
    if rotation:
        norm = math.sqrt(sum(x * x for x in result))
        result = tuple(x / norm for x in result)
    return result


action = doc['animations'][0]
decoded = {}
for channel in action['channels']:
    sampler = action['samplers'][channel['sampler']]
    if sampler.get('interpolation', 'LINEAR') != 'LINEAR':
        raise RuntimeError('Expected linear native animation samplers')
    decoded[channel['sampler']] = ([v[0] for v in read_accessor(sampler['input'])],
                                   read_accessor(sampler['output']))
    if channel['target']['path'] == 'scale' and any(abs(x - 1.0) > 0.00001 for v in decoded[channel['sampler']][1] for x in v):
        raise RuntimeError('Native rig contains non-unit animated bone scale')
doc['animations'] = []
for name, (first, last) in RANGES.items():
    start, end = first / 30.0, last / 30.0
    channels, samplers = [], []
    for channel in action['channels']:
        times, values = decoded[channel['sampler']]
        rotation = channel['target']['path'] == 'rotation'
        sample_times = [start] + [t for t in times if start < t < end] + [end]
        sampled = [interpolate(times, values, t, rotation) for t in sample_times]
        new_channel = copy.deepcopy(channel)
        new_channel['sampler'] = len(samplers)
        channels.append(new_channel)
        samplers.append({'input': append_accessor([(t - start,) for t in sample_times], 'SCALAR'),
                         'output': append_accessor(sampled, 'VEC4' if rotation else 'VEC3'),
                         'interpolation': 'LINEAR'})
    doc['animations'].append({'name': name, 'channels': channels, 'samplers': samplers})

# Keep source action nodes even after dropping the source gun's render geometry.
rename = {'g17_base': 'WeaponMotion', 'g17_magazine': 'MagazineMotion', 'g17_slide': 'SlideMotion'}
kept_meshes = set()
for node in doc['nodes']:
    if node.get('name') in rename:
        node['name'] = rename[node['name']]
    if 'mesh' in node:
        if 'skin' in node:
            kept_meshes.add(node['mesh'])
            node['name'] = 'BlackArmsMesh'
        else:
            del node['mesh']
mesh_map = {old: new for new, old in enumerate(sorted(kept_meshes))}
doc['meshes'] = [doc['meshes'][old] for old in sorted(kept_meshes)]
for node in doc['nodes']:
    if 'mesh' in node:
        node['mesh'] = mesh_map[node['mesh']]
used_materials = sorted({p['material'] for m in doc['meshes'] for p in m['primitives'] if 'material' in p})
material_map = {old: new for new, old in enumerate(used_materials)}
doc['materials'] = [doc['materials'][old] for old in used_materials]
for material in doc['materials']:
    # Source packed MR has a metallic cloth response in Godot; retain detail
    # maps while calibrating the derived gloves/sleeves as dark nonmetal cloth.
    pbr = material.setdefault('pbrMetallicRoughness', {})
    pbr['metallicFactor'] = 0.0
    pbr['roughnessFactor'] = 1.0
    pbr['baseColorFactor'] = [0.12, 0.12, 0.12, 1.0]
    pbr.pop('metallicRoughnessTexture', None)
for mesh in doc['meshes']:
    for primitive in mesh['primitives']:
        if 'material' in primitive:
            primitive['material'] = material_map[primitive['material']]


def texture_infos(value):
    if isinstance(value, dict):
        for key, child in value.items():
            if key.endswith('Texture') and isinstance(child, dict) and 'index' in child:
                yield child
            else:
                yield from texture_infos(child)
    elif isinstance(value, list):
        for child in value:
            yield from texture_infos(child)


infos = list(texture_infos(doc['materials']))
used_textures = sorted({info['index'] for info in infos})
texture_map = {old: new for new, old in enumerate(used_textures)}
doc['textures'] = [doc['textures'][old] for old in used_textures]
for info in infos:
    info['index'] = texture_map[info['index']]
used_images = sorted({texture['source'] for texture in doc['textures']})
image_map = {old: new for new, old in enumerate(used_images)}
doc['images'] = [doc['images'][old] for old in used_images]
for texture in doc['textures']:
    texture['source'] = image_map[texture['source']]

references = []
for mesh in doc['meshes']:
    for primitive in mesh['primitives']:
        for key in primitive['attributes']:
            references.append((primitive['attributes'], key))
        if 'indices' in primitive:
            references.append((primitive, 'indices'))
for skin in doc['skins']:
    references.append((skin, 'inverseBindMatrices'))
for animation in doc['animations']:
    for sampler in animation['samplers']:
        references.extend([(sampler, 'input'), (sampler, 'output')])
used_accessors = sorted({owner[key] for owner, key in references})
accessor_map = {old: new for new, old in enumerate(used_accessors)}
doc['accessors'] = [doc['accessors'][old] for old in used_accessors]
for owner, key in references:
    owner[key] = accessor_map[owner[key]]
view_refs = [(accessor, 'bufferView') for accessor in doc['accessors']]
view_refs += [(image, 'bufferView') for image in doc['images']]
used_views = sorted({owner[key] for owner, key in view_refs})
view_map = {old: new for new, old in enumerate(used_views)}
compact = bytearray()
views = []
for old in used_views:
    view = copy.deepcopy(doc['bufferViews'][old])
    while len(compact) % 4:
        compact.append(0)
    offset = view.get('byteOffset', 0)
    compact.extend(binary[offset:offset + view['byteLength']])
    view['byteOffset'] = len(compact) - view['byteLength']
    views.append(view)
doc['bufferViews'] = views
for owner, key in view_refs:
    owner[key] = view_map[owner[key]]
doc['buffers'] = [{'byteLength': len(compact)}]
doc.setdefault('asset', {}).setdefault('extras', {})['derived'] = 'Native arms only; documented actions split at 30 fps; original skin and joint rests retained'
doc['asset']['copyright'] = 'user77, DJMaesen, 3dvachevsky (CC-BY-4.0)'
doc['asset']['extras']['sources'] = [
    {'author': 'user77', 'source': 'https://sketchfab.com/models/7723ab14e70446ef8e06a134984f287f', 'license': 'https://creativecommons.org/licenses/by/4.0/', 'sha256': hashlib.sha256(blob).hexdigest()},
    {'author': 'DJMaesen', 'source': 'https://sketchfab.com/models/bd896167e7ca44f19597d3afe6a8d83f', 'license': 'https://creativecommons.org/licenses/by/4.0/', 'use': 'native black arms and animation'},
    {'author': '3dvachevsky', 'source': 'https://sketchfab.com/models/b4136758508c486cadcd96c74d7882b8', 'license': 'https://creativecommons.org/licenses/by/4.0/', 'use': 'original combined gun reference; its render meshes are excluded'},
]
doc['asset']['extras']['modifications'] = 'Documented actions sliced at 30 fps; source gun render geometry excluded; native skeleton/weights/inverse binds retained; gloves/sleeves calibrated as dark nonmetal cloth, retaining albedo/normal/AO detail.'
encoded = json.dumps(doc, separators=(',', ':')).encode('utf-8')
encoded += b' ' * ((-len(encoded)) % 4)
compact += b'\x00' * ((-len(compact)) % 4)
output = (struct.pack('<III', 0x46546c67, 2, 28 + len(encoded) + len(compact))
          + struct.pack('<II', len(encoded), 0x4e4f534a) + encoded
          + struct.pack('<II', len(compact), 0x004e4942) + compact)
DESTINATION.parent.mkdir(parents=True, exist_ok=True)
DESTINATION.write_bytes(output)
REPORT.parent.mkdir(parents=True, exist_ok=True)
record = {'source': str(SOURCE.relative_to(ROOT)), 'sha256': hashlib.sha256(blob).hexdigest(),
          'output': str(DESTINATION.relative_to(ROOT)), 'output_sha256': hashlib.sha256(output).hexdigest(),
          'joint_count': 60, 'source_fps': 30, 'clip_frame_ranges': RANGES,
          'rest_transforms_preserved': all({k: v for k, v in doc['nodes'][i].items() if k in ('matrix', 'translation', 'rotation', 'scale')} == {k: v for k, v in original_nodes[i].items() if k in ('matrix', 'translation', 'rotation', 'scale')} for i in original_skin[0]['joints']),
          'skin_joints_preserved': doc['skins'][0]['joints'] == original_skin[0]['joints']}
REPORT.write_text(json.dumps(record, indent=2), encoding='utf-8')
print('BLACK_ARMS_PREPARED', len(output), json.dumps(record), flush=True)
