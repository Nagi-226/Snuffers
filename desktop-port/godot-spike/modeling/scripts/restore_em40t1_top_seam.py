"""Join actual native upper shell cut edges to the original ring's upper edge.

This closes the visible top connection only. The source AI mesh contains other
open edges and folded boundary chains below this region; no whole-model
watertightness claim is made. Original shell/ring triangles are not moved.
Bridge UVs are interpolated from the existing native housing cut edge, using
its existing material. The original ring's UVs and material are untouched.
"""
import copy
import json
import math
import os
import sys
from collections import defaultdict

from restore_optic_shells import append_accessor, read_glb, triangle_area, write_glb
from restore_em40t1_shell import triangles
from restore_em40t1_cap_center import boundary_loops, cross, dot, edge_counts


def upper_shell_outline(vertices):
    counts = edge_counts(vertices, 7)
    values = {tuple(round(value,7) for value in v['POSITION']):v for v in vertices}
    edges = [(a,b) for (a,b),count in counts.items() if count == 1
             and abs(a[2]+.08)<1e-6 and abs(b[2]+.08)<1e-6
             and min(a[1],b[1]) > .19]
    graph = defaultdict(set)
    for a,b in edges:
        graph[a].add(b)
        graph[b].add(a)
    if any(len(neighbors)>2 for neighbors in graph.values()):
        raise RuntimeError('native top boundary has an ambiguous branch')
    seen, chains = set(), []
    for start in sorted(graph):
        if start in seen or len(graph[start]) != 1:
            continue
        chain, previous, current = [], None, start
        while current not in chain:
            chain.append(current)
            following = [p for p in graph[current] if p != previous]
            if not following:
                break
            previous,current = current,following[0]
        seen.update(chain)
        delta = sum(math.atan2(b[1]-.19,b[0])-math.atan2(a[1]-.19,a[0]) for a,b in zip(chain,chain[1:]))
        if delta < 0:
            chain.reverse()
        chains.append(chain)
    if seen != set(graph):
        raise RuntimeError('native top boundary contains an unexpected separate loop')
    chains.sort(key=lambda chain:math.atan2(chain[0][1]-.19,chain[0][0]))
    gaps = [math.dist(a[-1],b[0]) for a,b in zip(chains,chains[1:])]
    if max(gaps,default=0) > .002:
        raise RuntimeError('top boundary chains do not form the expected close native outline')
    outline = [values[p] for chain in chains for p in chain]
    outline_keys = [tuple(round(value,7) for value in v['POSITION']) for v in outline]
    if set(edges) - {tuple(sorted((a,b))) for a,b in zip(outline_keys,outline_keys[1:])}:
        raise RuntimeError('assembling the outline discarded a real native cut edge')
    return outline, edges, gaps


def parameterized(line):
    distances = [0.0]
    for a,b in zip(line,line[1:]):
        distances.append(distances[-1]+math.dist(a['POSITION'],b['POSITION']))
    return [value/distances[-1] for value in distances]


def source_at(line, parameters, fraction):
    for index in range(len(parameters)-1):
        if fraction <= parameters[index+1]+1e-12:
            alpha = (fraction-parameters[index])/(parameters[index+1]-parameters[index])
            return {name:tuple(a*(1-alpha)+b*alpha for a,b in zip(line[index][name],line[index+1][name])) for name in line[index]}
    return copy.deepcopy(line[-1])


def main(path):
    document,binary = read_glb(path)
    primitives = document['meshes'][0]['primitives']
    if len(primitives) != 4:
        raise RuntimeError('expected native shell, original ring, restored shell, restored center')
    shell = [v for i in [0,2] for v in triangles(document,binary,primitives[i])]
    ring = triangles(document,binary,primitives[1])
    if len(ring) != 184*3:
        raise RuntimeError('the original 184-face ring is required')
    native, native_edges, gaps = upper_shell_outline(shell)
    outer = next(loop for loop in boundary_loops(ring) if len(loop)==68)
    # Follow the true topology: the generated ring has slight angular folds.
    starts=[i for i,v in enumerate(outer) if v['POSITION'][1]>.19 and outer[i-1]['POSITION'][1]<=.19]
    if len(starts)!=1:
        raise RuntimeError('the native ring upper boundary is not one continuous path')
    upper=[]
    for step in range(len(outer)):
        vertex=outer[(starts[0]+step)%len(outer)]
        if vertex['POSITION'][1]<=.19:
            break
        upper.append(vertex)
    if upper[0]['POSITION'][0]<upper[-1]['POSITION'][0]:
        upper.reverse()
    ring_counts = edge_counts(ring,6)
    ring_edges = [tuple(sorted(tuple(round(x,6) for x in v['POSITION']) for v in [a,b])) for a,b in zip(upper,upper[1:])]
    if any(ring_counts[edge]!=1 for edge in ring_edges):
        raise RuntimeError('upper ring ordering does not preserve its real outer edges')
    nt,rt = parameterized(native),parameterized(upper)
    fitted = []
    for fraction,vertex in zip(rt,upper):
        mapped = source_at(native,nt,fraction)
        mapped['POSITION'] = vertex['POSITION']
        fitted.append(mapped)
    faces=[]
    i=j=0
    while i<len(native)-1 or j<len(fitted)-1:
        if j==len(fitted)-1 or (i<len(native)-1 and nt[i+1]<=rt[j+1]):
            faces.append([native[i],native[i+1],fitted[j]])
            i+=1
        else:
            faces.append([native[i],fitted[j+1],fitted[j]])
            j+=1
    names = primitives[0]['attributes']
    attributes = {name:[] for name in names}
    indices=[]
    added=[]
    for face in faces:
        face=copy.deepcopy(face)
        if triangle_area(face)<1e-15:
            raise RuntimeError('the seam generated a degenerate bridge face')
        a,b,c=[v['POSITION'] for v in face]
        normal=cross(tuple(b[k]-a[k] for k in range(3)),tuple(c[k]-a[k] for k in range(3)))
        centroid=[sum(v['POSITION'][k] for v in face)/3 for k in range(3)]
        if dot(normal,(centroid[0],centroid[1]-.19,0))<0:
            face.reverse()
            normal=tuple(-x for x in normal)
        length=math.sqrt(dot(normal,normal))
        for vertex in face:
            vertex['NORMAL']=tuple(x/length for x in normal)
            added.append(vertex)
            indices.append((len(attributes['POSITION']),))
            for name in attributes:
                attributes[name].append(vertex[name])
    counts7=edge_counts(shell+ring+added,7)
    if any(counts7[edge]!=2 for edge in native_edges):
        raise RuntimeError('one of the real upper native edges remains disconnected')
    counts6=edge_counts(shell+ring+added,6)
    if any(counts6[edge]!=2 for edge in ring_edges):
        raise RuntimeError('one of the real upper ring edges remains disconnected')
    primitive=copy.deepcopy(primitives[0])
    primitive['attributes']={name:append_accessor(document,binary,values,document['accessors'][names[name]]['type']) for name,values in attributes.items()}
    primitive['indices']=append_accessor(document,binary,indices,'SCALAR',5125)
    primitives.append(primitive)
    write_glb(path,document,binary)
    print(json.dumps({'native_upper_cut_edges_joined':len(native_edges),'original_upper_ring_edges_joined':len(ring_edges),
                      'native_small_gap_connections':len(gaps),'maximum_native_small_gap_m':max(gaps,default=0),
                      'bridge_triangles':len(faces),'original_ring_faces_retained':184,
                      'primitive_triangles':[len(triangles(document,binary,p))//3 for p in primitives],
                      'all_real_local_edge_incidence':2,'whole_model_watertight_claim':False,'output_bytes':os.path.getsize(path)},indent=2))


if __name__=='__main__':
    if len(sys.argv)!=2:
        raise SystemExit('usage: restore_em40t1_top_seam.py <current.glb>')
    main(os.path.abspath(sys.argv[1]))
