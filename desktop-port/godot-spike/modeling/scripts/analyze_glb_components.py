"""Print connected-component bounds for generated GLB part selection."""
import os
import sys
import trimesh

path = os.path.abspath(sys.argv[1])
scene = trimesh.load(path, force="scene")
mesh = scene.to_mesh()
parts = mesh.split(only_watertight=False)
rows = []
for part in parts:
    rows.append((len(part.faces), part.bounds[0], part.bounds[1], (part.bounds[0] + part.bounds[1]) * 0.5))
rows.sort(key=lambda row: row[0], reverse=True)
print("ASSET", path, "FACES", len(mesh.faces), "COMPONENTS", len(rows))
for index, (faces, lo, hi, center) in enumerate(rows[:120]):
    print(index, "faces", faces, "lo", lo.round(5).tolist(), "hi", hi.round(5).tolist(), "center", center.round(5).tolist())
