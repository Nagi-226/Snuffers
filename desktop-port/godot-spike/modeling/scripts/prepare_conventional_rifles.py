"""Prepare the owner-selected SIG516, SR25 and M700 for Godot.

Run with the existing Blender runtime:
  blender -b --factory-startup --python-exit-code 1 --python <this file>

Download originals remain outside the runtime assets. Source topology/UVs are
retained; the SR25 magazine follows its original author-assigned skin groups.
Working dimensions and attachment positions are asset measurements. Gameplay
parameters live in GameConfig, never in this offline preparation script.
"""
import hashlib
import json
import math
import struct
from pathlib import Path

import bpy
import bmesh
from mathutils import Matrix, Vector


ROOT = Path(__file__).resolve().parents[4]
DOWNLOADS = Path('C:/Users/FJL03/Downloads')
OUT = ROOT / 'godot/addons/community_weapons'
REPORT = ROOT / 'desktop-port/godot-spike/modeling/community_weapons/prepared_conventional_rifles.json'
MPX = OUT / 'mpx_tactical.glb'
RAW = ROOT / 'godot/raw_assets/community_weapons'
SOURCES = {
    'sig516': ('arctic_-_white_sig_516_sopmod.glb', 'N-GONE', 'a9ea47674b824665b4e3b58a28b149e8'),
    'sr25': ('low-poly_sr-25.glb', 'TastyTony', '81976c51d61543a288cf135fd7485951'),
    'm700': ('remington_model_700_.308_winchester_low_poly.glb', 'mehmetuysun', 'f55c2e95edd84b80b283e181d63e5ef6'),
    'scope': ('leupold_mk_4_lrt_m1_1040mm_scope_low-poly.glb', 'GoldbergR', 'bf0e3597985940408d24669297d15509'),
    'bipod': ('harris_bipod_low-poly.glb', 'GoldbergR', 'daa7dd1e247e453496974a5d252396f4'),
    'foregrip': ('foregrip.glb', 'elitej1gaming', '52781078a99c4e55934dab26a998875f'),
    'peq': ('low-poly_anpeq_15.glb', 'D_U', '522f6a04c34946dbb168022187645c1a'),
    'light': ('surefire_m600df_game_ready_flashlight.glb', 'mbvisuals1', 'c04c7a9b2f8346bd90c3938b0af8024a'),
}
records = []


def bounds(meshes):
    points = [o.matrix_world @ Vector(c) for o in meshes for c in o.bound_box]
    if not points:
        raise RuntimeError('No measured source mesh')
    return (Vector([min(p[k] for p in points) for k in range(3)]),
            Vector([max(p[k] for p in points) for k in range(3)]))


def count_triangles(meshes):
    total = 0
    for obj in meshes:
        obj.data.calc_loop_triangles()
        total += len(obj.data.loop_triangles)
    return total


def load_meshes(path, skinned=False):
    previous = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=str(path))
    # The glTF importer creates an Icosphere as an armature custom shape. It is
    # not one of the SR25's thirteen source mesh nodes and is never exported.
    meshes = [o for o in bpy.context.scene.objects if o not in previous and o.type == 'MESH'
              and (not skinned or any(m.type == 'ARMATURE' for m in o.modifiers))]
    if not meshes:
        raise RuntimeError('Missing source meshes: ' + str(path))
    for obj in meshes:
        obj['source_mesh'] = obj.name
    return meshes


def flatten(meshes):
    for obj in meshes:
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        for modifier in list(obj.modifiers):
            if modifier.type == 'ARMATURE':
                bpy.ops.object.modifier_apply(modifier=modifier.name)
        world = obj.matrix_world.copy()
        obj.parent = None
        obj.matrix_world = Matrix.Identity(4)
        obj.data.transform(world)
        obj.select_set(False)
    bpy.context.view_layer.update()


def apply_transform(meshes, transform):
    for obj in meshes:
        obj.data.transform(transform)
    bpy.context.view_layer.update()


def keep_objects(keep):
    # Remove imported authoring empties/helpers after world transforms are
    # baked. Otherwise duplicate names acquire .001 and break semantic groups.
    keep = set(keep)
    for obj in list(bpy.context.scene.objects):
        if obj not in keep:
            bpy.data.objects.remove(obj, do_unlink=True)


def normalize(meshes, scale, yaw, center):
    transform = Matrix.Rotation(math.radians(yaw), 4, 'Z') @ Matrix.Scale(scale, 4) @ Matrix.Translation(-center)
    apply_transform(meshes, transform)
    return transform


def root_node(name):
    root = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(root)
    return root


def group(name, meshes, parent, pivot=None):
    node = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(node)
    node.parent = parent
    if pivot is not None:
        node.location = pivot
    for i, obj in enumerate(meshes):
        obj.name = name + 'Part' + str(i + 1)
        obj.parent = node
        if pivot is not None:
            obj.data.transform(Matrix.Translation(-pivot))
    bpy.context.view_layer.update()
    return node


def marker(name, point, parent):
    node = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(node)
    node.parent = parent
    node.location = point
    return node


def component_meshes(root, component):
    candidates = [o for o in root.children_recursive if o.type == 'MESH'
                  and any(p.name == component for p in ancestors(o))]
    if not candidates:
        raise RuntimeError('Missing existing MPX accessory: ' + component)
    return candidates


def ancestors(obj):
    while obj.parent is not None:
        obj = obj.parent
        yield obj


def place_accessory(meshes, x, y, bottom=None, top=None, center_z=None):
    lo, hi = bounds(meshes)
    center = (lo + hi) * 0.5
    offset_z = bottom - lo.z if bottom is not None else top - hi.z if top is not None else center_z - center.z
    offset = Vector((x - center.x, y - center.y, offset_z))
    apply_transform(meshes, Matrix.Translation(offset))
    return offset


def source_info(key):
    filename, author, uid = SOURCES[key]
    path = (RAW if key in ['foregrip', 'peq', 'light'] else DOWNLOADS) / filename
    return {'file': filename, 'author': author, 'uid': uid,
            'source': 'https://sketchfab.com/models/' + uid,
            'license': 'https://creativecommons.org/licenses/by/4.0/',
            'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}


def finish(filename, root, meshes, keys, notes, measured_markers):
    OUT.mkdir(parents=True, exist_ok=True)
    for img in bpy.data.images:
        width, height = img.size
        if max(width, height) > 2048:
            factor = 2048.0 / max(width, height)
            img.scale(max(1, round(width * factor)), max(1, round(height * factor)))
    bpy.ops.object.select_all(action='DESELECT')
    root.select_set(True)
    for obj in root.children_recursive:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    path = OUT / filename
    bpy.ops.export_scene.gltf(filepath=str(path), export_format='GLB', use_selection=True,
                            export_yup=True, export_apply=True, export_cameras=False,
                            export_lights=False, export_animations=False, export_skins=False,
                            export_morph=False, export_draco_mesh_compression_enable=False)
    info = [source_info(key) for key in keys]
    blob = path.read_bytes()
    json_length = struct.unpack_from('<I', blob, 12)[0]
    gltf = json.loads(blob[20:20 + json_length])
    gltf['asset']['copyright'] = '; '.join(s['author'] + ' (CC-BY-4.0)' for s in info)
    gltf['asset']['extras'] = {'sources': info, 'prepared_on': '2026-11-18', 'modifications': notes}
    packed_json = json.dumps(gltf, separators=(',', ':')).encode('utf-8')
    packed_json += b' ' * (-len(packed_json) % 4)
    tail = blob[20 + json_length:]
    path.write_bytes(struct.pack('<III', 0x46546c67, 2, 20 + len(packed_json) + len(tail)) +
                     struct.pack('<II', len(packed_json), 0x4e4f534a) + packed_json + tail)
    lo, hi = bounds(meshes)
    groups = {}
    for node in root.children_recursive:
        if node.type != 'EMPTY':
            continue
        children = [o for o in node.children_recursive if o.type == 'MESH']
        if children:
            low, high = bounds(children)
            groups[node.name] = {'min': list(low), 'max': list(high), 'triangles': count_triangles(children)}
    record = {'output': str(path.relative_to(ROOT)), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
              'bytes': path.stat().st_size, 'triangles': count_triangles(meshes),
              'blender_bounds': [list(lo), list(hi)], 'blender_dimensions': list(hi - lo),
              'groups': groups, 'markers_blender': {k: list(v) for k, v in measured_markers.items()},
              'markers_godot': {k: [v.x, v.z, -v.y] for k, v in measured_markers.items()},
              'sources': info, 'modifications': notes, 'texture_max': 2048}
    records.append(record)
    print('CONVENTIONAL_PREPARED ' + json.dumps(record), flush=True)


def prepare_sig516():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    source = load_meshes(DOWNLOADS / SOURCES['sig516'][0])
    flatten(source)
    excluded = [o for o in source if o.name.startswith(('ITPIAL_', 'Foregrip_'))]
    rifle = [o for o in source if o not in excluded]
    source_triangles = count_triangles(source)
    replaced_triangles = count_triangles(excluded)
    keep_objects(rifle)
    lo, hi = bounds(rifle)
    center = Vector((0, (lo.y + hi.y) * 0.5, (lo.z + hi.z) * 0.5))
    transform = normalize(rifle, 0.001, 0, center)
    root = root_node('Sig516Tactical')
    magazine = [o for o in rifle if o.name.startswith('Pmag_')]
    acog = [o for o in rifle if o.name.startswith('ACOG_')]
    body = [o for o in rifle if o not in magazine and o not in acog]
    group('Body', body, root)
    mag_lo, mag_hi = bounds(magazine)
    group('Magazine', magazine, root, Vector(((mag_lo.x + mag_hi.x) * 0.5, (mag_lo.y + mag_hi.y) * 0.5, mag_hi.z)))
    group('ACOG', acog, root)
    # Existing MPX parts retain their already-checked forward direction and PBR.
    before_mpx = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=str(MPX))
    mpx_root = next(o for o in bpy.context.scene.objects if o not in before_mpx and o.name == 'MpxTactical')
    peq = component_meshes(mpx_root, 'InfraredModule')
    light = component_meshes(mpx_root, 'WeaponLight')
    grip = component_meshes(mpx_root, 'Foregrip')
    flatten(peq + light + grip)
    keep_objects(before_mpx | set(peq + light + grip))
    rail_top = float((transform @ Vector((0, 0, 90.1663208))).z)
    peq_offset = place_accessory(peq, 0, 0.105, bottom=rail_top + 0.0005)
    light_offset = place_accessory(light, 0.047, 0.16, center_z=0.045)
    place_accessory(grip, 0, 0.15, top=0.024)
    peq_root = group('InfraredModule', peq, root)
    light_root = group('WeaponLight', light, root)
    group('Foregrip', grip, root)
    points = {'Muzzle': transform @ Vector((0, 611.36730957, 58.4181323)),
              'OpticAim': transform @ Vector((0, -185.0, 123.5)),
              'LaserOrigin': Vector((-0.0346875, 0.245, 0.1264785)) + peq_offset,
              'FlashlightOrigin': Vector((0.03419285, 0.2825, 0.085192245)) + light_offset}
    marker('Muzzle', points['Muzzle'], root)
    marker('OpticAim', points['OpticAim'], root)
    marker('LaserOrigin', points['LaserOrigin'], peq_root)
    marker('FlashlightOrigin', points['FlashlightOrigin'], light_root)
    meshes = rifle + peq + light + grip
    if count_triangles(rifle) != source_triangles - replaced_triangles:
        raise RuntimeError('SIG516 original retained faces changed')
    finish('sig516_tactical.glb', root, meshes, ['sig516', 'foregrip', 'peq', 'light'],
           'Original SIG516/ACOG/suppressor retained at measured 1.097582m including suppressor; '
           'original ITPIAL and foregrip are replaced in this derivative by the existing MPX '
           'PEQ15/SureFire/foregrip, avoiding duplicates. PMAG is a complete separate source part. '
           'Retained source faces/UVs/PBR preserved; textures reduced to 2K; muzzle Godot -Z.', points)


def split_sr25_magazine(meshes):
    magazine = []
    body = []
    for obj in meshes:
        assigned = set()
        group_names = {g.index: g.name for g in obj.vertex_groups}
        for vertex in obj.data.vertices:
            if any(group_names.get(g.group) in ['mag_05', 'bullets_07'] and g.weight > 0.5 for g in vertex.groups):
                assigned.add(vertex.index)
        complete_faces = [p for p in obj.data.polygons if all(i in assigned for i in p.vertices)]
        if any(any(i in assigned for i in p.vertices) and not all(i in assigned for i in p.vertices) for p in obj.data.polygons):
            raise RuntimeError('SR25 magazine skin groups cross a source face: ' + obj.name)
        if not complete_faces:
            body.append(obj)
            continue
        if len(complete_faces) == len(obj.data.polygons):
            magazine.append(obj)
            continue
        copy = obj.copy()
        copy.data = obj.data.copy()
        bpy.context.scene.collection.objects.link(copy)
        copy['source_mesh'] = obj['source_mesh']
        for part, keep_magazine in [(obj, False), (copy, True)]:
            mesh = bmesh.new()
            mesh.from_mesh(part.data)
            mesh.verts.ensure_lookup_table()
            removed = [v for v in mesh.verts if (v.index in assigned) != keep_magazine]
            bmesh.ops.delete(mesh, geom=removed, context='VERTS')
            mesh.to_mesh(part.data)
            mesh.free()
        body.append(obj)
        magazine.append(copy)
    if not magazine:
        raise RuntimeError('SR25 original mag_05 skin group is missing')
    return body, magazine


def prepare_sr25():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    source = load_meshes(DOWNLOADS / SOURCES['sr25'][0], skinned=True)
    original_triangles = count_triangles(source)
    body, magazine = split_sr25_magazine(source)
    flatten(body + magazine)
    keep_objects(body + magazine)
    if count_triangles(body + magazine) != original_triangles:
        raise RuntimeError('SR25 body/magazine partition changed source face count')
    lo, hi = bounds(body + magazine)
    scale = 1.10 / (hi.x - lo.x)
    center = Vector(((lo.x + hi.x) * 0.5, 0, (lo.z + hi.z) * 0.5))
    normalize(body + magazine, scale, 90, center)
    root = root_node('SR25Precision')
    group('Body', body, root)
    mag_lo, mag_hi = bounds(magazine)
    group('Magazine', magazine, root, Vector(((mag_lo.x + mag_hi.x) * 0.5, (mag_lo.y + mag_hi.y) * 0.5, mag_hi.z)))
    before_scope = set(bpy.context.scene.objects)
    scope = load_meshes(DOWNLOADS / SOURCES['scope'][0])
    flatten(scope)
    keep_objects(before_scope | set(scope))
    normalize(scope, 1.0, 180, Vector((0, 0, 0)))
    glass = [o for o in scope if any('Glass' in m.name for m in o.data.materials if m)]
    if len(glass) != 1:
        raise RuntimeError('Expected one complete source Leupold glass mesh')
    optical = glass[0].data.materials[0].copy()
    optical.name = 'LeupoldOpticalGlass'
    optical.use_nodes = True
    optical.diffuse_color = (0.7, 0.85, 1.0, 0.06)
    optical.surface_render_method = 'DITHERED'
    bsdf = optical.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value = (0.7, 0.85, 1.0, 0.06)
    bsdf.inputs['Alpha'].default_value = 0.06
    bsdf.inputs['Metallic'].default_value = 0.0
    bsdf.inputs['Roughness'].default_value = 0.12
    glass[0].data.materials.clear()
    glass[0].data.materials.append(optical)
    scope_offset = place_accessory(scope, 0, -0.08, bottom=0.100)
    group('Scope', scope, root)
    before_bipod = set(bpy.context.scene.objects)
    bipod = load_meshes(DOWNLOADS / SOURCES['bipod'][0])
    flatten(bipod)
    keep_objects(before_bipod | set(bipod))
    left = [o for o in bipod if 'Leg' in o.name and '.001_' in o.name]
    right = [o for o in bipod if 'Leg' in o.name and o not in left]
    base = [o for o in bipod if o not in left and o not in right]
    if not left or not right:
        raise RuntimeError('Harris source must retain its two complete separate legs')
    # Actual fore-end underside is z=0.01958539m here; seat the original saddle
    # at z=0.020m for submillimetre contact instead of the former 64.66mm gap.
    place_accessory(bipod, 0, 0.34, top=0.020)
    bipod_root = group('Bipod', base, root)
    group('LeftLeg', left, bipod_root)
    group('RightLeg', right, bipod_root)
    barrel_point = Vector((403.1428223, 0, 33.0))
    transform = Matrix.Rotation(math.pi / 2, 4, 'Z') @ Matrix.Scale(scale, 4) @ Matrix.Translation(-center)
    points = {'Muzzle': transform @ barrel_point,
              'OpticAim': Vector((0, -0.171, 0)) + scope_offset}
    marker('Muzzle', points['Muzzle'], root)
    marker('OpticAim', points['OpticAim'], root)
    finish('sr25_precision.glb', root, body + magazine + scope + bipod, ['sr25', 'scope', 'bipod'],
           'SR25 working length 1.10m; original mag_05/bullets_07 weights partition complete '
           'faces into the detachable magazine; chamber bullet_06 stays with the body. '
           'Source rest skin is baked without replacing source geometry. Leupold Mk4 10x40 '
           'and Harris bipod retain their full mesh/UV/PBR, with independently grouped legs; '
           'the original Harris saddle seats on the measured handguard underside at Godot Y=0.020m. '
           'The original Leupold glass uses transparent optical material. Source materials have '
           'no textures; factor PBR/normals/UVs retained; muzzle Godot -Z.', points)


def prepare_m700():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    source = load_meshes(DOWNLOADS / SOURCES['m700'][0])
    original_triangles = count_triangles(source)
    flatten(source)
    keep_objects(source)
    lo, hi = bounds(source)
    center = Vector((0, (lo.y + hi.y) * 0.5, (lo.z + hi.z) * 0.5))
    transform = normalize(source, 1.0, 180, center)
    root = root_node('M700Scoped')
    bolt = [o for o in source if o.name.startswith(('bolt_', 'boltCap_', 'boltHandle_', 'firingPin_'))]
    internal = [o for o in source if o.name.startswith(('internalMag_', 'magSpring_'))]
    scope = [o for o in source if o.name.startswith(('bottomRing_', 'upperRing_', 'elevationTurret_', 'magnRing_', 'scope_', 'windTurret_', 'rail_'))]
    body = [o for o in source if o not in bolt and o not in internal and o not in scope]
    if len(bolt) != 4 or len(internal) != 2:
        raise RuntimeError('M700 source bolt/internal magazine components changed')
    group('Body', body, root)
    group('InternalMagazine', internal, root)
    group('Scope', scope, root)
    points = {'Muzzle': transform @ Vector((0, -0.6886533499, 0.320194646)),
              'OpticAim': transform @ Vector((0, 0.0993896723, 0.362347424)),
              'BoltPivot': transform @ Vector((0, 0.03794218, 0.320194646)),
              'BoltGrip': transform @ Vector((-0.029, 0.038, 0.285)),
              'RoundPort': transform @ Vector((0, -0.02, 0.327))}
    group('Bolt', bolt, root, points['BoltPivot'])
    for name in ['Muzzle', 'OpticAim', 'BoltGrip', 'RoundPort']:
        marker(name, points[name], root)
    if count_triangles(source) != original_triangles:
        raise RuntimeError('M700 retained source faces changed')
    finish('m700_scoped.glb', root, source, ['m700'],
           'Original M700 hunting rifle and its original scope/rings/turrets/rail retained '
           'at measured 1.054058m; no Leupold or bipod added. The four original bolt meshes '
           'share a shaft pivot; internal box/spring remain inside the stock. Source mesh '
           'faces/UV/PBR preserved; source scope contains no lens per author description. '
           'Textures 2K; muzzle Godot -Z.', points)


prepare_sig516()
prepare_sr25()
prepare_m700()
REPORT.parent.mkdir(parents=True, exist_ok=True)
REPORT.write_text(json.dumps(records, indent=2), encoding='utf-8')
print('CONVENTIONAL_RIFLES_COMPLETED ' + str(REPORT), flush=True)
