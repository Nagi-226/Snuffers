"""Prepare the approved MPX accessory assembly and a static G17 Gen5 candidate.

Run from the repository root with Blender --background --factory-startup
--python-exit-code 1 --python <this file>. Source GLBs remain unchanged.
Dimensions below are asset working scales, not weapon gameplay parameters.
"""
import hashlib
import json
import math
import struct
import sys
from pathlib import Path

import bpy
import bmesh
from mathutils import Matrix, Vector

ROOT = Path.cwd()
RAW = ROOT / 'godot/raw_assets/community_weapons'
OUT = ROOT / 'godot/addons/community_weapons'
REPORT = ROOT / 'desktop-port/godot-spike/modeling/community_weapons'
SOURCES = [
    ('sig_sauer_mpx.glb', 'michalstk11', 'd6e0a8020a7b4a9a876787ec91290022'),
    ('eotech_hws_exps_3.glb', 'Sambit_Raut', '04d1452515134866b8a97c3e7cb9a18e'),
    ('foregrip.glb', 'elitej1gaming', '52781078a99c4e55934dab26a998875f'),
    ('low-poly_anpeq_15.glb', 'D_U', '522f6a04c34946dbb168022187645c1a'),
    ('surefire_m600df_game_ready_flashlight.glb', 'mbvisuals1', 'c04c7a9b2f8346bd90c3938b0af8024a'),
    ('g17_gen_5_handgun__olight_-_nsw_police_force.glb', '8sianDude', '0200c248eba14385ad2bee8d4dc4e586'),
]
for name, _, _ in SOURCES:
    if not (RAW / name).is_file():
        raise FileNotFoundError(RAW / name)
OUT.mkdir(parents=True, exist_ok=True)
REPORT.mkdir(parents=True, exist_ok=True)
records = []


def bounds(meshes):
    points = [obj.matrix_world @ Vector(c) for obj in meshes for c in obj.bound_box]
    if not points:
        raise RuntimeError('No mesh bounds')
    return (Vector(tuple(min(p[k] for p in points) for k in range(3))),
            Vector(tuple(max(p[k] for p in points) for k in range(3))))


def load_meshes(filename):
    previous = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=str(RAW / filename))
    meshes = [o for o in bpy.context.scene.objects if o not in previous and o.type == 'MESH']
    if not meshes:
        raise RuntimeError('No source meshes: ' + filename)
    for obj in meshes:
        world = obj.matrix_world.copy()
        obj.parent = None
        obj.matrix_world = Matrix.Identity(4)
        obj.data.transform(world)
    bpy.context.view_layer.update()
    return meshes


def place(meshes, length, yaw, center_xy, bottom=None, top=None, center_z=None):
    lo, hi = bounds(meshes)
    scale = length / max(hi-lo)
    source_center = (lo+hi)*.5
    turn = Matrix.Rotation(math.radians(yaw), 4, 'Z')
    transform = turn @ Matrix.Scale(scale, 4) @ Matrix.Translation(-source_center)
    for obj in meshes:
        obj.data.transform(transform)
    bpy.context.view_layer.update()
    lo, hi = bounds(meshes)
    offset_z = bottom-lo.z if bottom is not None else top-hi.z if top is not None else center_z
    offset = Vector((center_xy[0], center_xy[1], offset_z))
    for obj in meshes:
        obj.data.transform(Matrix.Translation(offset))
    bpy.context.view_layer.update()
    return scale


def group(name, meshes, root):
    node = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(node)
    node.parent = root
    for index, obj in enumerate(meshes):
        obj['source_mesh'] = obj.name
        obj.name = name + 'Part' + str(index + 1)
        obj.parent = node
    return node


def root_node(name):
    node = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(node)
    return node


def finish(filename, root, meshes, source_indices, notes):
    lo, hi = bounds(meshes)
    center = (lo+hi)*.5
    for obj in meshes:
        obj.data.transform(Matrix.Translation(-center))
    bpy.context.view_layer.update()
    for image in bpy.data.images:
        width, height = image.size
        if max(width, height) > 2048:
            ratio = 2048 / max(width, height)
            image.scale(max(1, round(width*ratio)), max(1, round(height*ratio)))
    bpy.ops.object.select_all(action='DESELECT')
    root.select_set(True)
    for obj in meshes:
        obj.select_set(True)
        obj.parent.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    path = OUT / filename
    bpy.ops.export_scene.gltf(
        filepath=str(path), export_format='GLB', use_selection=True,
        export_yup=True, export_apply=True, export_cameras=False,
        export_lights=False, export_animations=False, export_skins=False,
        export_morph=False, export_draco_mesh_compression_enable=False)
    source_info = []
    for i in source_indices:
        name, author, uid = SOURCES[i]
        source_info.append({'file': name, 'author': author, 'uid': uid,
                            'source': 'https://sketchfab.com/models/' + uid,
                            'license': 'https://creativecommons.org/licenses/by/4.0/',
                            'sha256': hashlib.sha256((RAW/name).read_bytes()).hexdigest()})
    # Retain the complete author chain inside the derived GLB as well as the ledger.
    blob = path.read_bytes()
    json_length = struct.unpack_from('<I', blob, 12)[0]
    gltf = json.loads(blob[20:20+json_length])
    gltf['asset']['copyright'] = '; '.join(s['author'] + ' (CC-BY-4.0)' for s in source_info)
    gltf['asset']['extras'] = {'sources': source_info, 'prepared_on': '2026-11-10', 'modifications': notes}
    json_bytes = json.dumps(gltf, separators=(',', ':')).encode('utf-8')
    json_bytes += b' ' * (-len(json_bytes) % 4)
    tail = blob[20+json_length:]
    path.write_bytes(struct.pack('<III', 0x46546c67, 2, 20+len(json_bytes)+len(tail)) +
                     struct.pack('<II', len(json_bytes), 0x4e4f534a) + json_bytes + tail)
    lo, hi = bounds(meshes)
    triangles = 0
    for obj in meshes:
        obj.data.calc_loop_triangles()
        triangles += len(obj.data.loop_triangles)
    info = {'output': str(path.relative_to(ROOT)), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
            'bytes': path.stat().st_size, 'triangles': triangles,
            'blender_bounds': [list(lo), list(hi)], 'blender_dimensions': list(hi-lo),
            'groups': {node.name: {'min': list(bounds([o for o in meshes if o.parent == node])[0]),
                                   'max': list(bounds([o for o in meshes if o.parent == node])[1])}
                       for node in root.children},
            'sources': source_info, 'modifications': notes,
            'texture_max': 2048, 'removed_display_center': list(center)}
    records.append(info)
    print('PREPARED', json.dumps(info), flush=True)


def prepare_gen5():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    g17_root = root_node('G17Gen5Olight')
    g17 = load_meshes(SOURCES[5][0])
    # Source displays two spare magazines; the installed magazine also includes
    # a chamber cartridge as disconnected geometry, above the feed-lip round.
    spares = [o for o in g17 if o.name.startswith('mag_full.001_') or o.name.startswith('mag_empty_')]
    g17 = [o for o in g17 if o not in spares]
    for obj in spares:
        bpy.data.objects.remove(obj, do_unlink=True)
    installed = [o for o in g17 if o.name.startswith('mag_full_')]
    if len(installed) != 1:
        raise RuntimeError('Expected one installed Gen5 full magazine')
    magazine = installed[0]
    # Measured source-space separation: the chamber round (case plus projectile)
    # lies above z=1.06 and forward of y=.20. The installed feeding round is
    # behind y=.23; the polymer shell/feeding lips end below z=1.0474.
    cartridge_vertices = {v.index for v in magazine.data.vertices if v.co.z > 1.06 and v.co.y < .20}
    cartridge_faces = [p for p in magazine.data.polygons if all(i in cartridge_vertices for i in p.vertices)]
    if not cartridge_faces or any(any(i in cartridge_vertices for i in p.vertices) and not all(i in cartridge_vertices for i in p.vertices) for p in magazine.data.polygons):
        boundary = [p for p in magazine.data.polygons if any(i in cartridge_vertices for i in p.vertices) and not all(i in cartridge_vertices for i in p.vertices)]
        print('GEN5_SELECTION_DIAGNOSTIC', len(cartridge_vertices), len(cartridge_faces), [[list(magazine.data.vertices[i].co) for i in p.vertices] for p in boundary[:4]], flush=True)
        raise RuntimeError('Gen5 chamber selection does not preserve complete source faces')
    chamber = magazine.copy()
    chamber.data = magazine.data.copy()
    bpy.context.scene.collection.objects.link(chamber)
    chamber.name = 'Gen5ChamberRound'
    for obj, keep_cartridge in [(magazine, False), (chamber, True)]:
        mesh = bmesh.new()
        mesh.from_mesh(obj.data)
        mesh.verts.ensure_lookup_table()
        removed = [v for v in mesh.verts if (v.index in cartridge_vertices) != keep_cartridge]
        bmesh.ops.delete(mesh, geom=removed, context='VERTS')
        mesh.to_mesh(obj.data)
        mesh.free()
    g17.append(chamber)
    place(g17, .20, 180, (0, 0), center_z=0)
    for name, selector in [('Frame', 'g17_gen5_frame'), ('Slide', 'g17_gen5_slide'),
                           ('Magazine', 'g17_gen5_mag_fde'), ('WeaponLight', 'olight_pl2')]:
        parts = [o for o in g17 if o != chamber and any(selector in mat.name for mat in o.data.materials if mat)]
        if name == 'Frame':
            parts.append(chamber)
        if not parts:
            raise RuntimeError('Missing Gen5 part: ' + name)
        group(name, parts, g17_root)
    chamber.name = 'Gen5ChamberRound'
    finish('g17_gen5_olight.glb', g17_root, g17, [5],
           'Static Gen5 candidate, .20m working length; installed magazine and feeding round '
           'remain together, while the separate chamber cartridge follows the frame; excludes two '
           'displayed spare magazines; source faces and UVs retained; textures reduced to 2K; muzzle Godot -Z.')


if '--only-gen5' in sys.argv:
    report_path = REPORT / 'prepared_assets.json'
    if report_path.is_file():
        records.extend(record for record in json.loads(report_path.read_text(encoding='utf-8'))
                       if not record['output'].replace('\\', '/').endswith('/g17_gen5_olight.glb'))
    prepare_gen5()
    report_path.write_text(json.dumps(records, indent=2), encoding='utf-8')
    print('COMMUNITY_PREPARED_COMPLETED Gen5 only', flush=True)
    sys.exit(0)

bpy.ops.wm.read_factory_settings(use_empty=True)
mpx_root = root_node('MpxTactical')
body = load_meshes(SOURCES[0][0])
place(body, .65, 0, (0, 0), center_z=0)
group('Body', body, mpx_root)
# Measured rail top is z=.1495 and handguard underside z=.0759 after normalization.
optic = load_meshes(SOURCES[1][0])
glass_parts = [o for o in optic if o.name == 'scope022_low_EOTECH_HWS_EXPS_3_0']
if len(glass_parts) != 1 or len(glass_parts[0].data.polygons) != 12:
    raise RuntimeError('Expected the independently inspected twelve-face EOTech lens')
glass = bpy.data.materials.new('EotechOpticalGlass')
glass.use_nodes = True
glass.diffuse_color = (.70, .85, 1.0, .06)
glass.surface_render_method = 'DITHERED'
glass_bsdf = glass.node_tree.nodes.get('Principled BSDF')
glass_bsdf.inputs['Base Color'].default_value = (.70, .85, 1.0, .06)
glass_bsdf.inputs['Alpha'].default_value = .06
glass_bsdf.inputs['Metallic'].default_value = 0.0
glass_bsdf.inputs['Roughness'].default_value = .12
glass_parts[0].data.materials.clear()
glass_parts[0].data.materials.append(glass)
place(optic, .098, -90, (0, .015), bottom=.1445)
group('HolographicSight', optic, mpx_root)
foregrip = load_meshes(SOURCES[2][0])
place(foregrip, .12, 0, (0, .245), top=.077)
group('Foregrip', foregrip, mpx_root)
peq = load_meshes(SOURCES[3][0])
place(peq, .12, 90, (0, .185), bottom=.146)
group('InfraredModule', peq, mpx_root)
light = load_meshes(SOURCES[4][0])
place(light, .141, 90, (.043, .212), center_z=.115)
group('WeaponLight', light, mpx_root)
finish('mpx_tactical.glb', mpx_root, body+optic+foregrip+peq+light, range(5),
       'MPX working length .65m; four separately sourced accessories positioned on measured rails; '
       'source topology and UVs retained; the separate twelve-face EOTech lens uses transparent glass; '
       'foregrip moved forward 6cm following user review; textures reduced to 2K; muzzle Godot -Z; static asset only.')

prepare_gen5()
(REPORT / 'prepared_assets.json').write_text(json.dumps(records, indent=2), encoding='utf-8')
print('COMMUNITY_PREPARED_COMPLETED', len(records), flush=True)
