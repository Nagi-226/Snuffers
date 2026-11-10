"""Separate measured detachable magazine faces without changing their geometry or UVs.

Blender --background --factory-startup --python-exit-code 1 --python <this file>.
Each section is an inspected polygon in Godot's weapon-local Z/Y plane. Original
GLBs remain unchanged; the body and magazine together retain every source face.
"""
import hashlib
import json
import struct
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

ROOT = Path.cwd()
SOURCE = ROOT / 'godot/assets/models/weapons'
OUT = SOURCE
REPORT = ROOT / 'desktop-port/godot-spike/modeling/reload_magazines'
PREVIEW = ROOT / '.kimi-tmp/magazine_reload'
REGIONS = json.loads(Path(__file__).with_name('magazine_cut_regions.json').read_text())
REPORT.mkdir(parents=True, exist_ok=True)
PREVIEW.mkdir(parents=True, exist_ok=True)
SOURCE_TRIANGLES = []


def read_glb(path):
    blob = path.read_bytes()
    length = struct.unpack_from('<I',blob,12)[0]
    return json.loads(blob[20:20+length]), bytearray(blob[28+length:])


def accessor_values(document, binary, index):
    accessor = document['accessors'][index]
    if accessor['componentType'] != 5126 or accessor['type'] not in ('VEC2','VEC3') or 'sparse' in accessor:
        raise RuntimeError('Expected dense float32 vertex data')
    size = 2 if accessor['type'] == 'VEC2' else 3
    view = document['bufferViews'][accessor['bufferView']]
    offset = view.get('byteOffset',0)+accessor.get('byteOffset',0)
    stride = view.get('byteStride',size*4)
    if stride < size*4 or stride % 4:
        raise RuntimeError('Invalid float32 vertex stride')
    return [struct.unpack_from('<'+'f'*size,binary,offset+i*stride) for i in range(accessor['count'])]


def source_triangles(path):
    document,binary=read_glb(path)
    if any(any(key in node for key in ('matrix','translation','rotation','scale')) for node in document['nodes']):
        raise RuntimeError('Source transform requires explicit normal remapping')
    result=[]
    for primitive in document['meshes'][0]['primitives']:
        attributes=primitive['attributes']
        points=accessor_values(document,binary,attributes['POSITION'])
        uvs=accessor_values(document,binary,attributes['TEXCOORD_0'])
        normals=accessor_values(document,binary,attributes['NORMAL'])
        if primitive.get('mode',4) != 4:
            raise RuntimeError('Expected source triangles')
        accessor=document['accessors'][primitive['indices']]
        if accessor['type'] != 'SCALAR' or 'sparse' in accessor:
            raise RuntimeError('Expected dense triangle indices')
        code,size={5121:('B',1),5123:('H',2),5125:('I',4)}[accessor['componentType']]
        view=document['bufferViews'][accessor['bufferView']]
        offset=view.get('byteOffset',0)+accessor.get('byteOffset',0)
        stride=view.get('byteStride',size)
        indices=[struct.unpack_from('<'+code,binary,offset+i*stride)[0] for i in range(accessor['count'])]
        for i in range(0,len(indices),3):
            result.append([(points[v],uvs[v],normals[v]) for v in indices[i:i+3]])
    return result


def inside(point, polygon):
    x, y = point
    result = False
    previous = polygon[-1]
    for current in polygon:
        ax, ay = previous; bx, by = current
        if (ay > y) != (by > y) and x < (bx - ax) * (y - ay) / (by - ay) + ax:
            result = not result
        previous = current
    return result


def in_section(point, polygon, margin):
    if inside(point, polygon):
        return True
    point = Vector(point)
    for a, b in zip(polygon, polygon[1:] + polygon[:1]):
        a = Vector(a); b = Vector(b)
        edge = b - a
        t = max(0.0, min(1.0, (point - a).dot(edge) / edge.length_squared))
        if (point - (a + edge * t)).length <= margin:
            return True
    return False


def make_part(source, indices, name, pivot, parent):
    old = source.data
    matrix = source.matrix_world
    normal_matrix = matrix.to_3x3().inverted().transposed()
    vertex_ids = sorted({v for i in indices for v in old.polygons[i].vertices})
    mapping = {v: i for i, v in enumerate(vertex_ids)}
    vertices = [matrix @ old.vertices[i].co - pivot for i in vertex_ids]
    faces = [tuple(mapping[v] for v in old.polygons[i].vertices) for i in indices]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    for material in old.materials:
        mesh.materials.append(material)
    normals = []
    source_loops = []
    for polygon, i in zip(mesh.polygons, indices):
        polygon.material_index = old.polygons[i].material_index
        polygon.use_smooth = old.polygons[i].use_smooth
        for loop in old.polygons[i].loop_indices:
            source_loops.append(loop)
            normals.append((normal_matrix @ old.corner_normals[loop].vector).normalized())
    for layer in old.uv_layers:
        target = mesh.uv_layers.new(name=layer.name)
        for index, loop in enumerate(source_loops):
            target.data[index].uv = layer.data[loop].uv
    mesh.normals_split_custom_set(normals)
    mesh.update()
    # Blender encodes custom normals relative to a smooth fan, which can change
    # by ~0.45 degrees when faces split. Carry source float32 normals as a corner
    # attribute so the exporter also keeps vertices with distinct source normals.
    raw_normals=mesh.attributes.new(name='_RAW_NORMAL',type='FLOAT_VECTOR',domain='CORNER')
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.parent = parent
    obj.location = pivot
    # Verify the split before export, against source corners rather than just
    # face counts: vertices, UVs, shading normals and material assignments.
    for polygon, index in zip(mesh.polygons, indices):
        original = old.polygons[index]
        if polygon.material_index != original.material_index:
            raise RuntimeError('Material changed while separating '+name)
        for corner, (new_loop, old_loop) in enumerate(zip(polygon.loop_indices, original.loop_indices)):
            new_point = mesh.vertices[mesh.loops[new_loop].vertex_index].co + pivot
            old_point = matrix @ old.vertices[old.loops[old_loop].vertex_index].co
            if (new_point-old_point).length > 0.0000002:
                raise RuntimeError('Source vertex changed while separating '+name)
            for layer in old.uv_layers:
                if (mesh.uv_layers[layer.name].data[new_loop].uv-layer.data[old_loop].uv).length > 0.0000001:
                    raise RuntimeError('Source UV changed while separating '+name)
            source_uv=old.uv_layers[0].data[old_loop].uv
            source_point, source_texcoord, raw=SOURCE_TRIANGLES[index][corner]
            if max(abs(a-b) for a,b in zip((old_point.x,old_point.z,-old_point.y),source_point)) > 0.0000002 or max(abs(a-b) for a,b in zip((source_uv.x,1.0-source_uv.y),source_texcoord)) > 0.0000002:
                raise RuntimeError('Source triangle/corner order changed: '+name+' face='+str(index)+' corner='+str(corner))
            raw_normals.data[new_loop].vector=raw
    return obj


def render(parts, region, label, offset=0.0):
    body, magazine = parts
    direction = 1.0 if region['direction'] == 'up' else -1.0
    magazine.location.z += direction * offset
    bpy.context.view_layer.update()
    body.color = (.42,.48,.56,1); magazine.color = (1.0,.16,.06,1)
    points = [o.matrix_world @ v.co for o in parts for v in o.data.vertices]
    lo = Vector(tuple(min(p[k] for p in points) for k in range(3)))
    hi = Vector(tuple(max(p[k] for p in points) for k in range(3)))
    center=(lo+hi)*.5
    scene=bpy.context.scene
    scene.render.engine='BLENDER_WORKBENCH'
    scene.render.resolution_x=960;scene.render.resolution_y=540
    scene.render.resolution_percentage=100
    scene.display.shading.light='STUDIO';scene.display.shading.color_type='OBJECT'
    scene.display.shading.show_cavity=True
    scene.world=bpy.data.worlds.new('PreviewWorld');scene.world.color=(.15,.15,.15)
    scene.view_settings.view_transform='Standard'
    data=bpy.data.cameras.new('Camera');data.type='ORTHO'
    # Blender ortho_scale is horizontal at this landscape aspect ratio.
    data.ortho_scale=max(hi.y-lo.y, (hi.z-lo.z)*scene.render.resolution_x/scene.render.resolution_y)*1.15
    cam=bpy.data.objects.new('Camera',data);scene.collection.objects.link(cam)
    cam.location=center+Vector((1,0,0))*max(hi-lo)*3
    cam.rotation_euler=(center-cam.location).to_track_quat('-Z','Y').to_euler()
    scene.camera=cam;scene.render.filepath=str(PREVIEW/(region['weapon']+'_'+label+'.png'))
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam,do_unlink=True)
    magazine.location.z -= direction * offset
    bpy.context.view_layer.update()


reports=[]
jobs=[]
for region in REGIONS:
    jobs.append(region)
    if 'intact_source' in region:
        variant = dict(region)
        variant['source'] = region['intact_source']
        variant['source_sha256'] = region['intact_sha256']
        variant['variant'] = 'intact'
        jobs.append(variant)
selected = sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
for region in jobs:
    if selected and region['weapon'] not in selected:
        continue
    path=SOURCE/region['source']
    source_hash=hashlib.sha256(path.read_bytes()).hexdigest()
    if source_hash != region['source_sha256']:
        raise RuntimeError('Source changed; re-inspect magazine section: '+str(path))
    bpy.ops.wm.read_factory_settings(use_empty=True)
    SOURCE_TRIANGLES=source_triangles(path)
    bpy.ops.import_scene.gltf(filepath=str(path))
    meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']
    if len(meshes)!=1:
        raise RuntimeError('Expected the inspected single-mesh source')
    source=meshes[0]
    if len(source.data.polygons) != len(SOURCE_TRIANGLES):
        raise RuntimeError('Source triangle count changed during import')
    mag_faces=[];body_faces=[]
    for face in source.data.polygons:
        center=source.matrix_world @ face.center
        polygon = region['section_godot_zy']
        margin = region.get('edge_margin',0.0)
        points = [source.matrix_world @ source.data.vertices[v].co for v in face.vertices]
        # Border strips can have their centroid outside while two corners belong
        # to the measured magazine. Keep that whole original triangle with it.
        selected_corners = sum(in_section((-p.y,p.z),polygon,margin) for p in points)
        is_magazine = in_section((-center.y,center.z),polygon,margin) or selected_corners >= 2
        (mag_faces if is_magazine else body_faces).append(face.index)
    if len(mag_faces)<100 or len(body_faces)<100:
        raise RuntimeError('Measured section failed to identify substantial magazine/body geometry')
    points=[source.matrix_world @ source.data.vertices[v].co for i in mag_faces for v in source.data.polygons[i].vertices]
    lo=Vector(tuple(min(p[k] for p in points) for k in range(3)))
    hi=Vector(tuple(max(p[k] for p in points) for k in range(3)))
    pivot=Vector(((lo.x+hi.x)*.5,(lo.y+hi.y)*.5,lo.z if region['direction']=='up' else hi.z))
    root=bpy.data.objects.new('ReloadViewmodel',None);bpy.context.scene.collection.objects.link(root)
    body=make_part(source,body_faces,'Body',Vector((0,0,0)),root)
    magazine=make_part(source,mag_faces,'DetachableMagazine',pivot,root)
    source_face_count=len(source.data.polygons)
    if len(body.data.polygons)+len(magazine.data.polygons)!=source_face_count or set(body_faces)&set(mag_faces):
        raise RuntimeError('Source faces lost while separating magazine')
    # Keep every original triangle, corner normal, material and UV corner; source is read only.
    bpy.data.objects.remove(source,do_unlink=True)
    bpy.context.view_layer.update()
    length=hi.z-lo.z
    extraction=length+.035
    render([body,magazine],region,'split')
    render([body,magazine],region,'pulled',extraction)
    bpy.ops.object.select_all(action='DESELECT')
    for obj in [root,body,magazine]:obj.select_set(True)
    bpy.context.view_layer.objects.active=body
    output=OUT/(path.stem+'_reload.glb')
    bpy.ops.export_scene.gltf(filepath=str(output),export_format='GLB',use_selection=True,
                             export_yup=True,export_apply=False,export_cameras=False,
                             export_lights=False,export_animations=False,export_skins=False,
                             export_morph=False,export_attributes=True,export_draco_mesh_compression_enable=False)
    blob=output.read_bytes();json_length=struct.unpack_from('<I',blob,12)[0]
    document=json.loads(blob[20:20+json_length])
    # Blender's exporter snaps sub-micrometre translations to zero. Preserve
    # the exact measured magazine pivot rather than moving its source vertices.
    for node in document['nodes']:
        if node.get('name') == 'DetachableMagazine':
            node['translation']=[pivot.x,pivot.z,-pivot.y]
    binary=bytearray(blob[28+json_length:])
    for mesh in document['meshes']:
        for primitive in mesh['primitives']:
            attributes=primitive['attributes']
            raw=accessor_values(document,binary,attributes.pop('_RAW_NORMAL'))
            target=document['accessors'][attributes['NORMAL']]
            if target['componentType'] != 5126 or target['type'] != 'VEC3' or target['count'] != len(raw):
                raise RuntimeError('Export normal accessor format changed')
            view=document['bufferViews'][target['bufferView']]
            offset=view.get('byteOffset',0)+target.get('byteOffset',0)
            stride=view.get('byteStride',12)
            if stride < 12 or stride % 4:
                raise RuntimeError('Export normal accessor stride invalid')
            for i,normal in enumerate(raw):
                struct.pack_into('<fff',binary,offset+i*stride,*normal)
            if accessor_values(document,binary,attributes['NORMAL']) != raw:
                raise RuntimeError('Source float32 normal bytes not retained')
    document['asset']['extras']={'source_asset':str(path.relative_to(ROOT)).replace('\\','/'),
                                'source_sha256':source_hash,'prepared_on':'2026-11-10',
                                'modifications':'Separated measured magazine faces; original geometry, UVs, normals and PBR materials retained.'}
    encoded=json.dumps(document,separators=(',',':')).encode();encoded+=b' '*(-len(encoded)%4)
    tail=struct.pack('<II',len(binary),0x004e4942)+binary
    output.write_bytes(struct.pack('<III',0x46546c67,2,20+len(encoded)+len(tail))+
                       struct.pack('<II',len(encoded),0x4e4f534a)+encoded+tail)
    if hashlib.sha256(path.read_bytes()).hexdigest()!=source_hash:
        raise RuntimeError('Original source mutated')
    row={'weapon':region['weapon'],'source':str(path.relative_to(ROOT)).replace('\\','/'),
         'variant':region.get('variant','viewmodel'),
         'source_sha256':source_hash,'output':str(output.relative_to(ROOT)).replace('\\','/'),
         'output_sha256':hashlib.sha256(output.read_bytes()).hexdigest(),
         'source_faces':source_face_count,'body_faces':len(body_faces),'magazine_faces':len(mag_faces),
         'magazine_bounds_godot':[[lo.x,lo.z,-hi.y],[hi.x,hi.z,-lo.y]],
         'magazine_pivot_godot':[pivot.x,pivot.z,-pivot.y],
         'extraction_direction':region['direction'],'extraction_distance':extraction,
         'grip_offset':[-(hi.x-lo.x)*.5-.005, (hi.z+lo.z)*.5-pivot.z,0.0],
         'retained_faces':len(body_faces)+len(mag_faces),'original_unchanged':True,
         'verified_vertices_uvs_normals_materials':True}
    reports.append(row)
    print('MAGAZINE_SPLIT',json.dumps(row),flush=True)
(REPORT/'prepared_magazines.json').write_text(json.dumps(reports,indent=2))
print('MAGAZINE_SPLIT_COMPLETED',len(reports),flush=True)
