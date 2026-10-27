"""Open the JB-02 rear cargo doorway while preserving all other geometry."""
import os
import trimesh

source = os.path.abspath("godot/assets/models/vehicles/jb02_apc.glb")
output = os.path.abspath("desktop-port/godot-spike/modeling/units/jb-02/jb02_open.glb")
scene = trimesh.load(source, force="scene")
mesh = scene.to_mesh()
centers = mesh.triangles_center
opening = (
    (centers[:, 2] > 2.0)
    & (abs(centers[:, 0]) < 1.55)
    & (centers[:, 1] > 0.5)
    & (centers[:, 1] < 2.2)
)
removed = int(opening.sum())
if removed == 0:
    raise RuntimeError("cargo doorway matched no faces")
mesh.update_faces(~opening)
mesh.export(output)
print("JB02_OPEN removed_faces", removed, "remaining", len(mesh.faces), "output", output)
