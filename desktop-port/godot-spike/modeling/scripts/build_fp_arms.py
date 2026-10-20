#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""EM-68A / EM-57P 第一人称手臂（前臂 + 战术手套）程序化建模器 —— 派单 18。

设计要点
========
1. **在武器局部空间建模**：手臂顶点直接落在武器 GLB 的坐标系里
   （glTF/Godot 约定：X 右、Y 上、+Z 朝后、枪口 -Z），
   所以把 `arms_<stem>.glb` 作为武器实例节点的子节点、局部变换恒等即可对齐。
2. **比例按武器尺度**：EM-68A 的 GLB 是 1:1 米制；EM-57P 的 GLB 被放大了
   （场景里用 scale 0.4 缩回），因此手臂按 `hand_scale` 放大，
   保证「手 / 枪」比例与真实一致（两把枪不共用尺寸）。
3. **零武器改动**：武器 GLB 只读；输出 GLB 里只有手臂网格，不含任何武器几何。
4. **贴图 1024² 内嵌**：baseColor（作战服布料 + 手套皮革）、emissive（青蓝发光条纹）、
   ORM（roughness/metallic/occlusion）；左臂手背上方留 EDAA 臂章 UV 区。
5. **可复跑**：`blender -b --factory-startup --python-exit-code 1 --python build_fp_arms.py -- em68a`
   不带参数则两把枪都跑。

验收相关
========
* 单只手臂三角面 ≤ 15000（脚本内硬断言）。
* 武器 GLB sha256 前后一致（脚本内硬断言）。
* 穿模自检：手臂顶点对武器网格做最近面查询，统计「陷进武器表面 > tol」的顶点数与最大深度。
* 输出报告 JSON（供 md 报告引用），可选 `--render` 出 Workbench 三视图。
"""

import hashlib
import json
import math
import os
import struct
import sys

import bpy
import bmesh
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

# --------------------------------------------------------------------------------------
# 路径
# --------------------------------------------------------------------------------------
HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", "..", ".."))
WEAPON_DIR = os.path.join(REPO, "godot", "assets", "models", "weapons")
OUT_DIR = os.path.join(HERE, "out")
RENDER_DIR = os.path.join(REPO, "desktop-port", "godot-spike", "modeling", "em-weapons", "renders_fp_arms")

TEX_SIZE = 1024
TRI_BUDGET_PER_ARM = 15000

# --------------------------------------------------------------------------------------
# 贴图 UV 分区（归一化 [0,1]）
# --------------------------------------------------------------------------------------
UV_SLEEVE = (0.020, 0.020, 0.470, 0.470)   # 作战服布料（含青蓝条纹）
UV_GLOVE = (0.510, 0.020, 0.980, 0.470)    # 手套皮革
UV_PAD = (0.020, 0.530, 0.470, 0.980)      # 护掌 / 指节护片
UV_PATCH = (0.510, 0.530, 0.980, 0.980)    # EDAA 臂章

# --------------------------------------------------------------------------------------
# 两个武器的姿态参数
# --------------------------------------------------------------------------------------
# 手部基准尺寸（EM-68A / 米制 1:1 尺度下的「武器局部单位」）
HAND = dict(
    palm_len=0.098,     # 腕 -> 指根
    palm_w=0.086,       # 掌宽
    palm_t=0.031,       # 掌厚
    finger=[0.0455, 0.0280, 0.0210],   # 食指/中指/无名指/小指 三段长度基准
    finger_r=0.0108,
    thumb_seg=[0.0430, 0.0330],
    thumb_r=0.0128,
    fore_len=0.250,     # 腕 -> 肘
    fore_r=0.031,
    cuff_r=0.040,
)

PARAMS = {
    "em68a": dict(
        weapon="em68a_viewmodel.glb",
        out="arms_em68a.glb",
        hand_scale=1.0,
        grip_look=(0.0, -0.115, 0.205),   # 握把中心（glTF 局部空间，仅用于调姿特写机位）
        right=dict(
            wrist=(0.074, -0.105, 0.352),
            clear_dir=(1.0, 0.0, 0.0),          # 避让方向：远离握把（向右）
            finger_dir=(-0.34, 0.10, -0.935),   # 腕 -> 指根（朝前略偏左）
            palm_normal=(-0.90, 0.05, -0.43),   # 掌心朝左前（贴握把右侧面）
            elbow_dir=(0.46, -0.38, 0.81),      # 腕 -> 肘（向右后下，避开枪托）
            spread=(0.0, 1.0, 0.0),             # 四指沿握把轴向「向上」堆叠：食指最高
            curl=(25.0, 58.0, 55.0),            # 先直行到握把前缘、再依次扣回来包住前方
            index_curl=(10.0, 30.0, 20.0),      # 扣扳机的食指：接近伸直
            spread_deg=(4.0, 0.0, -4.0, -9.0),  # 四指展开角（食/中/无名/小）
            thumb_dir=(0.10, -0.24, -0.96),
            thumb_curl=(26.0, 30.0),
            finger_len_scale=(0.96, 1.00, 0.95, 0.82),
        ),
        left=dict(
            wrist=(-0.034, -0.132, -0.232),
            clear_dir=(0.0, -1.0, 0.0),         # 避让方向：从护木下方离开
            finger_dir=(0.22, 0.52, -0.83),     # 从下方托住护木、指尖朝上
            palm_normal=(0.18, 0.90, 0.40),     # 掌心朝上（贴护木下缘）
            elbow_dir=(-0.52, -0.52, 0.68),
            spread=(0.0, 0.0, 1.0),
            curl=(52.0, 56.0, 34.0),
            index_curl=(44.0, 50.0, 30.0),
            spread_deg=(4.0, 0.0, -4.0, -9.0),
            thumb_dir=(-0.55, 0.30, -0.78),
            thumb_curl=(30.0, 26.0),
            finger_len_scale=(0.96, 1.00, 0.95, 0.82),
        ),
    ),
    "em57p": dict(
        weapon="em57p_viewmodel.glb",
        out="arms_em57p.glb",
        hand_scale=2.50,   # 场景里 EM-57P 用 scale 0.4 缩回 -> GLB 局部单位 2.5 倍于米
        grip_look=(0.0, -0.235, 0.240),   # 握把中心（glTF 局部空间，仅用于调姿特写机位）
        right=dict(
            wrist=(0.150, -0.262, 0.560),
            clear_dir=(1.0, 0.0, 0.0),
            finger_dir=(-0.34, 0.10, -0.935),
            palm_normal=(-0.90, 0.05, -0.43),
            elbow_dir=(0.46, -0.36, 0.81),
            spread=(0.0, 1.0, 0.0),
            curl=(25.0, 58.0, 55.0),
            index_curl=(12.0, 32.0, 22.0),
            spread_deg=(4.0, 0.0, -4.0, -9.0),
            thumb_dir=(0.06, -0.30, -0.95),
            thumb_curl=(28.0, 32.0),
            finger_len_scale=(0.96, 1.00, 0.95, 0.82),
        ),
        left=dict(
            wrist=(-0.150, -0.300, 0.600),
            clear_dir=(-1.0, 0.0, 0.0),
            finger_dir=(0.30, 0.06, -0.95),
            palm_normal=(0.90, 0.05, -0.43),
            elbow_dir=(-0.44, -0.40, 0.80),
            spread=(0.0, 1.0, 0.0),
            curl=(40.0, 44.0, 32.0),
            index_curl=(20.0, 28.0, 18.0),
            spread_deg=(4.0, 0.0, -4.0, -9.0),
            thumb_dir=(-0.30, 0.55, -0.78),
            thumb_curl=(24.0, 22.0),
            finger_len_scale=(0.96, 1.00, 0.95, 0.82),
        ),
    ),
}


# --------------------------------------------------------------------------------------
# 小工具
# --------------------------------------------------------------------------------------
def log(msg):
    print("[arms] %s" % msg)


def v3(t):
    return Vector((float(t[0]), float(t[1]), float(t[2])))


def norm(t):
    v = v3(t)
    return v.normalized()


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def rot_toward(vec, toward, angle_deg):
    """把 vec 绕 axis=cross(vec,toward) 旋转 angle，使其向 toward 靠拢。"""
    v = Vector(vec)
    axis = v.cross(Vector(toward))
    if axis.length < 1e-9:
        return v
    axis.normalize()
    return (Matrix.Rotation(math.radians(angle_deg), 3, axis) @ v)


def smoothstep(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3.0 - 2.0 * t)


class Part(object):
    """一个子网格：顶点 + 面 + 每面角 UV（UV 直接由参数化坐标给出）。"""

    def __init__(self, name):
        self.name = name
        self.verts = []
        self.faces = []
        self.face_uvs = []

    def add(self, p):
        self.verts.append((float(p[0]), float(p[1]), float(p[2])))
        return len(self.verts) - 1

    def face(self, idx, uvs):
        self.faces.append(tuple(idx))
        self.face_uvs.append([(float(u), float(v)) for (u, v) in uvs])

    # -- 放样：rings 是若干圈（每圈点数相同），首尾相连成面 ---------------------------
    def loft(self, rings, uv_rect, cap_start=True, cap_end=True, closed=True):
        u0, v0, u1, v1 = uv_rect
        n = len(rings[0])
        base = []
        for ring in rings:
            base.append([self.add(p) for p in ring])
        m = len(rings)
        for i in range(m - 1):
            va = v0 + (v1 - v0) * (i / float(m - 1))
            vb = v0 + (v1 - v0) * ((i + 1) / float(m - 1))
            for j in range(n if closed else n - 1):
                j2 = (j + 1) % n
                ua = u0 + (u1 - u0) * (j / float(n))
                ub = u0 + (u1 - u0) * ((j + 1) / float(n))
                self.face([base[i][j], base[i][j2], base[i + 1][j2], base[i + 1][j]],
                          [(ua, va), (ub, va), (ub, vb), (ua, vb)])
        if cap_start:
            self.face(base[0], [(u0 + (u1 - u0) * (j / float(n)), v0) for j in range(n)])
        if cap_end:
            self.face(list(reversed(base[-1])),
                      [(u0 + (u1 - u0) * (j / float(n)), v1) for j in range(n)])

    # -- 球形/圆头帽子 -----------------------------------------------------------------
    def cap_dome(self, ring, center, normal, radius, uv_rect, steps=2, flip=False):
        u0, v0, u1, v1 = uv_rect
        n = len(ring)
        rings = [ring]
        base_ids = [[self.add(p) for p in ring]]
        nrm = Vector(normal).normalized()
        for k in range(1, steps + 1):
            a = (math.pi / 2.0) * (k / float(steps))
            r = radius * math.cos(a)
            d = radius * math.sin(a)
            newring = []
            for p in ring:
                rel = Vector(p) - Vector(center)
                tangential = rel - nrm * rel.dot(nrm)
                if tangential.length > 1e-9:
                    tangential = tangential.normalized() * r
                newring.append(Vector(center) + nrm * d + tangential)
            ids = [self.add(p) for p in newring]
            base_ids.append(ids)
            rings.append(newring)
        for i in range(len(base_ids) - 1):
            va = v0 + (v1 - v0) * (i / float(len(base_ids) - 1))
            vb = v0 + (v1 - v0) * ((i + 1) / float(len(base_ids) - 1))
            for j in range(n):
                j2 = (j + 1) % n
                ua = u0 + (u1 - u0) * (j / float(n))
                ub = u0 + (u1 - u0) * ((j + 1) / float(n))
                quad = [base_ids[i][j], base_ids[i][j2], base_ids[i + 1][j2], base_ids[i + 1][j]]
                uvs = [(ua, va), (ub, va), (ub, vb), (ua, vb)]
                if flip:
                    quad = list(reversed(quad))
                    uvs = list(reversed(uvs))
                self.face(quad, uvs)
        tip = [self.add(Vector(center) + nrm * radius)]
        for j in range(n):
            j2 = (j + 1) % n
            tri = [base_ids[-1][j], base_ids[-1][j2], tip[0]]
            if flip:
                tri = list(reversed(tri))
            self.face(tri, [(u0, v1), (u1, v1), ((u0 + u1) / 2, v1)])


def ellipse_ring(center, axis_a, axis_b, ra, rb, sides):
    pts = []
    for i in range(sides):
        a = 2.0 * math.pi * i / sides
        pts.append(Vector(center) + axis_a * (math.cos(a) * ra) + axis_b * (math.sin(a) * rb))
    return pts


def superellipse_ring(center, axis_a, axis_b, ra, rb, sides, power=3.2):
    """圆角矩形截面（手套掌部/指节用），power 越大越方。"""
    pts = []
    for i in range(sides):
        a = 2.0 * math.pi * i / sides
        ca, sa = math.cos(a), math.sin(a)
        x = math.copysign(abs(ca) ** (2.0 / power), ca) * ra
        y = math.copysign(abs(sa) ** (2.0 / power), sa) * rb
        pts.append(Vector(center) + axis_a * x + axis_b * y)
    return pts


def frame_from(dir_vec, up_hint):
    f = Vector(dir_vec).normalized()
    up = Vector(up_hint)
    if abs(f.dot(up.normalized())) > 0.98:
        up = Vector((1.0, 0.0, 0.0)) if abs(f.x) < 0.7 else Vector((0.0, 0.0, 1.0))
    a = f.cross(up)
    if a.length < 1e-9:
        a = f.cross(Vector((1.0, 0.0, 0.0)))
    a.normalize()
    b = f.cross(a).normalized()
    return a, b   # a, b 与 f 正交


# --------------------------------------------------------------------------------------
# 手部构建
# --------------------------------------------------------------------------------------
def build_hand(part, side, pose, s, pad_part):
    """构建手套 + 前臂；返回关键点（用于报告）。side: 'right' | 'left'。"""
    H = {k: (v * s if isinstance(v, float) else v) for k, v in HAND.items()}

    wrist = v3(pose["wrist"])
    f = norm(pose["finger_dir"])            # 腕 -> 指根
    n = norm(pose["palm_normal"])           # 掌心朝外
    # 正交化
    n = (n - f * n.dot(f)).normalized()
    spread_axis = norm(pose["spread"])
    spread_axis = (spread_axis - f * spread_axis.dot(f) - n * spread_axis.dot(n)).normalized()
    hinge = f.cross(n).normalized()          # 指关节屈曲轴

    palm_len = H["palm_len"]
    palm_w = H["palm_w"]
    palm_t = H["palm_t"]

    # ---- 腕部到指根的掌体：三段放样（腕/掌中/指根） --------------------------------
    rings = []
    for t, wf, tf in ((0.0, 0.72, 0.92), (0.35, 0.92, 1.0), (0.72, 1.0, 0.96), (1.0, 0.95, 0.80)):
        c = wrist + f * (palm_len * t)
        rings.append(superellipse_ring(c, spread_axis, n,
                                      palm_w * 0.5 * wf, palm_t * 0.5 * tf, 14, power=3.4))
    part.loft(rings, UV_GLOVE, cap_start=True, cap_end=False)

    knuckle_center = wrist + f * palm_len
    report = {"wrist": list(wrist), "knuckle_center": list(knuckle_center)}

    # ---- 四指 ---------------------------------------------------------------------
    names = ("index", "middle", "ring", "pinky")
    offs = (0.42, 0.14, -0.14, -0.40)     # 沿 spread_axis 的指根偏移（掌宽比例）
    lenscale = pose["finger_len_scale"]
    for i, name in enumerate(names):
        base = knuckle_center + spread_axis * (offs[i] * palm_w) + n * (palm_t * 0.10) - f * (palm_len * 0.03)
        segs = [H["finger"][k] * lenscale[i] for k in range(3)]
        curl = pose["curl"] if name != "index" else pose["index_curl"]
        ang = pose["spread_deg"][i]
        d = rot_toward(f, spread_axis, ang)
        radius = H["finger_r"] * (1.0 - 0.10 * i)
        pts = [base]
        cur = Vector(d)
        for k in range(3):
            cur = rot_toward(cur, n, curl[k])
            pts.append(pts[-1] + cur * segs[k])
        # 关节球 + 指节管（每段一个放样，半径递减）
        for k in range(3):
            r0 = radius * (1.0 - 0.14 * k)
            r1 = radius * (1.0 - 0.14 * (k + 1))
            a, b = frame_from(pts[k + 1] - pts[k], n)
            rings = []
            for t, rr in ((0.0, r0), (0.5, (r0 + r1) * 0.5 * 1.02), (1.0, r1)):
                c = pts[k] + (pts[k + 1] - pts[k]) * t
                rings.append(superellipse_ring(c, a, b, rr, rr * 0.92, 10, power=2.4))
            part.loft(rings, UV_GLOVE if k else UV_PAD, cap_start=True, cap_end=True)
        report.setdefault("fingers", {})[name] = {"base": list(pts[0]), "tip": list(pts[-1]),
                                                 "joints": [list(p) for p in pts[1:]]}

    # ---- 拇指 ---------------------------------------------------------------------
    tb = wrist + f * (palm_len * 0.22) - spread_axis * (palm_w * 0.46) + n * (palm_t * 0.30)
    td = rot_toward(norm(pose["thumb_dir"]), spread_axis, -18.0)
    pts = [tb]
    cur = Vector(td)
    for k in range(2):
        cur = rot_toward(cur, n, pose["thumb_curl"][k])
        pts.append(pts[-1] + cur * H["thumb_seg"][k])
    for k in range(2):
        r0 = H["thumb_r"] * (1.0 - 0.10 * k)
        r1 = H["thumb_r"] * (1.0 - 0.10 * (k + 1))
        a, b = frame_from(pts[k + 1] - pts[k], n)
        rings = []
        for t, rr in ((0.0, r0), (0.55, (r0 + r1) * 0.52), (1.0, r1)):
            c = pts[k] + (pts[k + 1] - pts[k]) * t
            rings.append(superellipse_ring(c, a, b, rr, rr * 0.9, 10, power=2.3))
        part.loft(rings, UV_PAD if k == 0 else UV_GLOVE, cap_start=(k == 0), cap_end=True)
    report["thumb"] = {"base": list(pts[0]), "tip": list(pts[-1])}

    # ---- 前臂（袖管）：腕 -> 肘，含袖口 + 褶皱环 ----------------------------------
    elbow = wrist + norm(pose["elbow_dir"]) * H["fore_len"]
    fa = (wrist - elbow).normalized()
    a, b = frame_from(fa, n)
    steps = 9
    rings = []
    for i in range(steps + 1):
        t = i / float(steps)
        c = elbow + (wrist - elbow) * t
        # 腕部略细，袖口（t≈0.86）鼓起，肘部粗
        if t < 0.80:
            r = H["fore_r"] * (1.0 + 0.55 * (1.0 - t / 0.80))
            rt = r * 0.92
        else:
            k = (t - 0.80) / 0.20
            r = H["fore_r"] * (1.0 - 0.10 * k) + H["cuff_r"] * smoothstep(k * 1.6) * (1.0 - smoothstep((k - 0.55) * 2.2))
            rt = r * 0.94
        # 布料褶皱：沿轴向的轻微半径起伏
        r *= 1.0 + 0.035 * math.sin(t * 26.0)
        rings.append(ellipse_ring(c, a, b, r, rt, 16))
    part.loft(rings, UV_SLEEVE, cap_start=True, cap_end=True)
    report["elbow"] = list(elbow)

    # ---- 左臂 EDAA 臂章贴片（手背上方） -------------------------------------------
    if side == "left":
        # 手背 = -n 侧，贴在掌体前段
        c = wrist + f * (palm_len * 0.55) - n * (palm_t * 0.54)
        a1 = spread_axis
        a2 = f
        w, hgt = palm_w * 0.46, palm_len * 0.42
        quad = [c - a1 * w * 0.5 - a2 * hgt * 0.5, c + a1 * w * 0.5 - a2 * hgt * 0.5,
                c + a1 * w * 0.5 + a2 * hgt * 0.5, c - a1 * w * 0.5 + a2 * hgt * 0.5]
        u0, v0, u1, v1 = UV_PATCH
        ids = [pad_part.add(p) for p in quad]
        pad_part.face(ids, [(u0, v0), (u1, v0), (u1, v1), (u0, v1)])
        report["patch_center"] = list(c)

    return report


# --------------------------------------------------------------------------------------
# 贴图生成（PIL）
# --------------------------------------------------------------------------------------
def write_png(path, rgb):
    """最小 PNG 写出器（RGB8，无依赖；Blender 内置 Python 没有 PIL）。"""
    import zlib
    h, w, _ = rgb.shape
    raw = bytearray()
    for y in range(h):
        raw.append(0)
        raw.extend(rgb[y].tobytes())

    def chunk(tag, payload):
        return (struct.pack(">I", len(payload)) + tag + payload +
                struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF))

    ihdr = struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)
    data = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) +
            chunk(b"IDAT", zlib.compress(bytes(raw), 6)) + chunk(b"IEND", b""))
    with open(path, "wb") as f:
        f.write(data)
    return path


def _urect(uv):
    """UV 矩形 -> (y0, y1, x0, x1) 像素范围（图像坐标：行 0 在顶部，写出时原样）。"""
    S = TEX_SIZE
    x0, y0 = int(uv[0] * S), int(uv[1] * S)
    x1, y1 = int(uv[2] * S), int(uv[3] * S)
    return y0, y1, x0, x1


def _fill(arr, uv, rgb):
    y0, y1, x0, x1 = _urect(uv)
    arr[y0:y1, x0:x1] = rgb


def _outline(arr, uv, rgb, t=2):
    y0, y1, x0, x1 = _urect(uv)
    arr[y0:y0 + t, x0:x1] = rgb
    arr[y1 - t:y1, x0:x1] = rgb
    arr[y0:y1, x0:x0 + t] = rgb
    arr[y0:y1, x1 - t:x1] = rgb


def _hband(arr, uv, v_frac, half_px, rgb):
    y0, y1, x0, x1 = _urect(uv)
    y = y0 + int((y1 - y0) * v_frac)
    arr[max(0, y - half_px):y + half_px, x0:x1] = rgb


def _box_blur(arr, k=2):
    out = arr.astype(np.float32)
    for _ in range(2):
        pad = np.pad(out, ((1, 1), (1, 1), (0, 0)), mode="edge")
        out = (pad[:-2, 1:-1] + pad[2:, 1:-1] + pad[1:-1, :-2] + pad[1:-1, 2:]) * 0.25
    return np.clip(out, 0, 255).astype(np.uint8)


def build_textures(out_dir):
    os.makedirs(out_dir, exist_ok=True)
    S = TEX_SIZE
    rng = np.random.RandomState(7)
    base = np.zeros((S, S, 3), dtype=np.float32)
    base[:, :] = (14, 16, 20)
    emis = np.zeros((S, S, 3), dtype=np.float32)
    orm = np.zeros((S, S, 3), dtype=np.float32)
    orm[:, :] = (255, 200, 20)                       # R=occlusion G=roughness B=metallic

    # --- 作战服布料 ---
    _fill(base, UV_SLEEVE, (26, 30, 38))
    _fill(orm, UV_SLEEVE, (255, 205, 26))
    y0, y1, x0, x1 = _urect(UV_SLEEVE)
    noise = rng.normal(0.0, 5.0, (y1 - y0, x1 - x0, 1))
    base[y0:y1, x0:x1] += noise
    for vv in (0.10, 0.245, 0.305, 0.42):            # 袖管横向接缝/罗纹
        _hband(base, UV_SLEEVE, vv, 1, (16, 19, 24))
    for vv in (0.165, 0.285, 0.355):                 # 青蓝发光条纹（前臂纵向）
        _hband(emis, UV_SLEEVE, vv, 2, (70, 235, 255))
        _hband(base, UV_SLEEVE, vv, 2, (34, 96, 112))
        _hband(orm, UV_SLEEVE, vv, 2, (255, 90, 30))

    # --- 手套皮革 ---
    _fill(base, UV_GLOVE, (38, 38, 42))
    _fill(orm, UV_GLOVE, (255, 150, 45))
    gy0, gy1, gx0, gx1 = _urect(UV_GLOVE)
    gnoise = rng.normal(0.0, 4.5, (gy1 - gy0, gx1 - gx0, 1))
    base[gy0:gy1, gx0:gx1] += gnoise
    for vv in (0.06, 0.50, 0.94):                    # 手套掌部/指节的缝合线
        _hband(base, UV_GLOVE, vv, 1, (22, 23, 27))

    # --- 护掌 / 指节护片 ---
    _fill(base, UV_PAD, (22, 24, 28))
    _fill(orm, UV_PAD, (255, 110, 60))
    _outline(base, UV_PAD, (40, 80, 92), t=3)
    _outline(emis, UV_PAD, (40, 200, 225), t=2)

    # --- EDAA 臂章 ---
    _fill(base, UV_PATCH, (18, 21, 26))
    _fill(orm, UV_PATCH, (255, 120, 35))
    _outline(base, UV_PATCH, (60, 110, 125), t=4)
    py0, py1, px0, px1 = _urect(UV_PATCH)
    cy, cx = (py0 + py1) // 2, (px0 + px1) // 2
    ry, rx = int((py1 - py0) * 0.26), int((px1 - px0) * 0.20)
    ys = np.arange(py0, py1)[:, None]
    xs = np.arange(px0, px1)[None, :]
    dy = np.abs(ys - cy) / float(ry)
    dx = np.abs(xs - cx) / float(rx)
    diamond = (dx + dy) <= 1.0
    ring = diamond & ~((dx + dy) <= 0.82)
    base[py0:py1, px0:px1][ring] = (44, 130, 148)
    emis[py0:py1, px0:px1][ring] = (70, 235, 255)
    bar = (np.abs(xs - cx) <= 3) & (np.abs(ys - (cy - int(ry * 0.45))) <= int(ry * 0.55))
    base[py0:py1, px0:px1][bar] = (70, 235, 255)
    emis[py0:py1, px0:px1][bar] = (70, 235, 255)
    # 臂章外圈的青色细描边（发光更明显）
    emis = _box_blur(emis, 2)

    paths = {}
    for name, arr in (("base", base), ("emissive", emis), ("orm", orm)):
        p = os.path.join(out_dir, "arms_%s.png" % name)
        write_png(p, np.clip(arr, 0, 255).astype(np.uint8))
        paths[name] = p
    return paths


# --------------------------------------------------------------------------------------
# Blender 场景装配 / 导出
# --------------------------------------------------------------------------------------
def gltf_to_blender(p):
    """glTF/Godot 局部坐标 (X 右, Y 上, Z 后) -> Blender 场景坐标 (X 右, Y 后, Z 上)。

    Blender 的 glTF 导入器会绕 X 轴 +90° 把 Y-up 转成 Z-up，即 (x, y, z)_gltf -> (x, -z, y)。
    手臂的姿态锚点全部按 glTF/Godot 局部空间实测得到，落网格时必须做同一变换，
    否则会和导入后的武器差一个 90°（首版就是因为缺这个变换导致手飘到机匣上方、穿模 0.278 m）。
    """
    x, y, z = float(p[0]), float(p[1]), float(p[2])
    return (x, -z, y)


def make_object(name, parts, materials):
    verts, faces, uvs = [], [], []
    for part in parts:
        off = len(verts)
        verts.extend(gltf_to_blender(p) for p in part.verts)
        for fidx, f in enumerate(part.faces):
            faces.append(tuple(i + off for i in f))
            uvs.append(part.face_uvs[fidx])
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    layer = mesh.uv_layers.new(name="UVMap")
    li = 0
    for face_uvs in uvs:
        for uv in face_uvs:
            layer.data[li].uv = uv
            li += 1
    for poly in mesh.polygons:
        poly.use_smooth = True
    # 放样的封盖面绕序可能与相邻侧面相反 -> 统一朝外，避免出现「黑洞」观感
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    obj.data.materials.append(materials)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def build_material(tex_paths):
    mat = bpy.data.materials.new("arms_mat")
    mat.use_nodes = True
    nt = mat.node_tree
    for node in list(nt.nodes):
        nt.nodes.remove(node)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

    def tex(path, colorspace="sRGB"):
        img = bpy.data.images.load(path)
        img.colorspace_settings.name = colorspace
        node = nt.nodes.new("ShaderNodeTexImage")
        node.image = img
        node.interpolation = "Smart"
        return node

    base = tex(tex_paths["base"])
    emis = tex(tex_paths["emissive"])
    orm = tex(tex_paths["orm"], "Non-Color")
    nt.links.new(base.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(emis.outputs["Color"], bsdf.inputs["Emission Color"])
    bsdf.inputs["Emission Strength"].default_value = 2.2
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(orm.outputs["Color"], sep.inputs["Color"])
    nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
    nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])
    bsdf.inputs["IOR"].default_value = 1.45
    return mat


def import_weapon(path):
    bpy.ops.import_scene.gltf(filepath=path)
    return [o for o in bpy.context.scene.objects if o.type == "MESH"]


def build_armature_objects(stem, cfg, tex_paths):
    """返回 (arm_objs, 关键点报告)"""
    s = cfg["hand_scale"]
    mat = build_material(tex_paths)
    key = {}
    objs = []
    for side in ("right", "left"):
        main = Part("%s_arm_%s" % (stem, side))
        pad = Part("%s_arm_%s_patch" % (stem, side))
        key[side] = build_hand(main, side, cfg[side], s, pad)
        parts = [main]
        if side == "left":
            parts.append(pad)
        obj = make_object("%s_arm_%s" % (stem, side), parts, mat)
        objs.append(obj)
    return objs, key


def tri_count(obj):
    obj.data.calc_loop_triangles()
    return len(obj.data.loop_triangles)


def penetration_check(arm_objs, weapon_objs, tol=0.002):
    """手臂顶点 vs 武器网格：统计陷进表面 > tol 的顶点数与最大深度。"""
    from mathutils import Vector as V
    trees = []
    for w in weapon_objs:
        bvh = BVHTree.FromObject(w, bpy.context.evaluated_depsgraph_get())
        mw = w.matrix_world.copy()
        trees.append((bvh, mw, mw.inverted()))

    PROBE_DIRS = (Vector((0.1357, 0.2714, 0.9531)).normalized(),
                  Vector((-0.8123, 0.3111, 0.4938)).normalized(),
                  Vector((0.4477, -0.7241, 0.5248)).normalized())

    def inside_parity(bvh, p, direction):
        """单方向射线奇偶判内外。"""
        count = 0
        origin = Vector(p)
        for _ in range(48):
            loc, _nrm, _idx, dist = bvh.ray_cast(origin, direction, 6.0)
            if loc is None:
                break
            count += 1
            origin = loc + direction * 1e-6
        return count % 2 == 1

    def inside_all_dirs(bvh, p):
        """三个方向都对=内部。武器网格是 AI 生成的分块壳体（非闭合流形），
        单方向奇偶会被开放边界骗出假阳性，多方向一致才采信。"""
        for d in PROBE_DIRS:
            if not inside_parity(bvh, p, d):
                return False
        return True

    per_obj = {}
    total = 0
    for a in arm_objs:
        mw = a.matrix_world.copy()
        inside = 0
        worst = 0.0
        worst_at = None
        for v in a.data.vertices:
            p = mw @ v.co
            total += 1
            for bvh, wmw, wiw in trees:
                loc = wiw @ p
                hit = bvh.find_nearest(loc)
                if hit[0] is None:
                    continue
                point, normal, index, dist = hit
                if not inside_all_dirs(bvh, loc):
                    continue
                d = dist / wmw.to_scale().x if wmw.to_scale().x else dist
                if d > tol:
                    inside += 1
                    if d > worst:
                        worst = d
                        worst_at = list(p)
                    break
        per_obj[a.name] = {"verts": len(a.data.vertices), "inside_over_tol": inside,
                           "max_penetration_m": round(worst, 6),
                           "worst_world_pos": [round(c, 5) for c in worst_at] if worst_at else None}
    inside = sum(o["inside_over_tol"] for o in per_obj.values())
    worst = max((o["max_penetration_m"] for o in per_obj.values()), default=0.0)
    return {"verts": total, "inside_over_tol": inside,
            "max_penetration_m": round(worst, 6), "tol_m": tol, "per_object": per_obj}


def export_glb(path, objs):
    for o in bpy.context.scene.objects:
        o.select_set(o in objs)
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        export_yup=True,
        export_apply=False,
        use_selection=True,
        use_visible=False,
        export_cameras=False,
        export_lights=False,
        export_animations=False,
        export_skins=False,
        export_morph=False,
        export_extras=False,
        export_texcoords=True,
        export_normals=True,
        export_tangents=False,
        export_materials="EXPORT",
        export_image_format="AUTO",
        export_keep_originals=False,
        export_draco_mesh_compression_enable=False,
    )


# --------------------------------------------------------------------------------------
# 渲染
# --------------------------------------------------------------------------------------
def setup_workbench():
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sh = sc.display.shading
    sh.light = "STUDIO"
    sh.color_type = "TEXTURE"
    sh.show_cavity = True
    sh.cavity_type = "BOTH"
    sh.curvature_ridge_factor = 1.0
    sh.curvature_valley_factor = 1.0
    sh.show_shadows = True
    sc.render.film_transparent = False
    sc.render.image_settings.file_format = "PNG"
    sc.render.resolution_x = 1100
    sc.render.resolution_y = 800


def add_camera(loc, look_at, ortho=None, lens=50.0):
    cam_data = bpy.data.cameras.new("cam")
    cam = bpy.data.objects.new("cam", cam_data)
    bpy.context.scene.collection.objects.link(cam)
    cam.location = Vector(loc)
    direction = Vector(look_at) - Vector(loc)
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    if ortho:
        cam_data.type = "ORTHO"
        cam_data.ortho_scale = ortho
    else:
        cam_data.lens = lens
    bpy.context.scene.camera = cam
    return cam


def render_views(stem, out_dir, focus, ortho, extra=None):
    os.makedirs(out_dir, exist_ok=True)
    setup_workbench()
    sc = bpy.context.scene
    sc.world = None
    shots = []

    def shoot(name, loc, look, ortho_scale=None, lens=None):
        for o in list(bpy.context.scene.objects):
            if o.type == "CAMERA":
                bpy.data.objects.remove(o, do_unlink=True)
        add_camera(loc, look, ortho=ortho_scale, lens=lens or 50.0)
        p = os.path.join(out_dir, "%s_%s.png" % (stem, name))
        sc.render.filepath = p
        bpy.ops.render.render(write_still=True)
        shots.append(p)
        return p

    # 侧视：相机在 +X 看 -X（Blender 里武器长轴是 Y，正好侧对）
    shoot("side", (focus[0] + 1.35 * ortho / 1.15, focus[1], focus[2]), focus, ortho_scale=ortho)
    # 正视：从枪口侧（glTF -Z == Blender -Y）看过去
    shoot("front", (focus[0], focus[1] - 1.35 * ortho / 1.15, focus[2]), focus, ortho_scale=ortho)
    for name, loc, look, lens in (extra or []):
        shoot(name, loc, look, lens=lens)
    return shots


def gltf_images(path):
    with open(path, "rb") as f:
        data = f.read()
    magic, ver, length = struct.unpack_from("<III", data, 0)
    off = 12
    js = None
    while off < len(data):
        clen, ctype = struct.unpack_from("<II", data, off)
        chunk = data[off + 8: off + 8 + clen]
        if ctype == 0x4E4F534A:
            js = json.loads(chunk.decode("utf-8"))
            break
        off += 8 + clen + ((4 - clen % 4) % 4)
    imgs = []
    for im in js.get("images", []):
        imgs.append({"mime": im.get("mimeType"), "name": im.get("name")})
    return {"images": imgs, "materials": len(js.get("materials", [])),
            "meshes": len(js.get("meshes", [])), "nodes": len(js.get("nodes", [])),
            "bytes": length}


# --------------------------------------------------------------------------------------
# 主流程
# --------------------------------------------------------------------------------------
def run(stem, do_render=False):
    cfg = PARAMS[stem]
    weapon_path = os.path.join(WEAPON_DIR, cfg["weapon"])
    out_glb = os.path.join(WEAPON_DIR, cfg["out"])
    log("=" * 78)
    log("%s : %s" % (stem, os.path.basename(weapon_path)))
    log("=" * 78)

    w_sha_before = sha256(weapon_path)
    w_bytes_before = os.path.getsize(weapon_path)
    log("weapon sha256(before) = %s (%d B)" % (w_sha_before, w_bytes_before))

    bpy.ops.wm.read_factory_settings(use_empty=True)
    weapon_objs = import_weapon(weapon_path)
    wobj_copy = list(weapon_objs)

    tex_paths = build_textures(OUT_DIR)
    arm_objs, key = build_armature_objects(stem, cfg, tex_paths)
    for o in arm_objs:
        log("built %-22s tris=%6d verts=%6d" % (o.name, tri_count(o), len(o.data.vertices)))

    tris = {o.name: tri_count(o) for o in arm_objs}
    per_arm = {}
    for o in arm_objs:
        side = "right" if "right" in o.name else "left"
        per_arm[side] = tris[o.name]
    assert max(per_arm.values()) <= TRI_BUDGET_PER_ARM, "三角面预算超限: %s" % per_arm

    pen = penetration_check(arm_objs, weapon_objs, tol=0.002)
    log("penetration: %s" % json.dumps(pen))

    # ---- 自动避让：若仍有穿插，把该手沿「远离武器」方向整体外移穿透量 ----------
    # 目的：把「手指埋进握把」的接触穿插压到 2 mm 容差内（宁可留极小缝隙也不穿模）。
    moved = {}
    fit_passes = 0
    for _pass in range(3):
        pending = False
        for o in arm_objs:
            info = pen["per_object"].get(o.name, {})
            depth = info.get("max_penetration_m") or 0.0
            if depth <= 0.0025:
                continue
            side = "right" if "right" in o.name else "left"
            cdir = cfg[side].get("clear_dir")
            if not cdir:
                continue
            delta = Vector(gltf_to_blender(cdir)).normalized() * (depth + 0.0025)
            o.location = o.location + delta
            bpy.context.view_layer.update()
            rec = moved.setdefault(o.name, {"dir": list(cdir), "moved_m": 0.0})
            rec["moved_m"] = round(rec["moved_m"] + delta.length, 5)
            pending = True
        if not pending:
            break
        fit_passes += 1
        pen = penetration_check(arm_objs, weapon_objs, tol=0.002)
        log("penetration after auto-fit pass %d: %s" % (_pass + 1, json.dumps(pen)))

    merged = {
        "auto_fit_passes": fit_passes,
        "after_fit": pen,
        "moved": moved,
        "inside_over_tol": pen["inside_over_tol"],
        "max_penetration_m": pen["max_penetration_m"],
        "tol_m": 0.002,
        "per_object": pen["per_object"],
    }
    pen = merged

    if do_render:
        focus = Vector((0.0, 0.0, 0.0))       # 武器/手臂局部原点（Blender 场景里就是原点）
        ortho = 1.15 * cfg["hand_scale"]      # pistol 的 GLB 局部单位是米的 2.5 倍，取景同比放大
        # --- 真机挂载（只读 player.tscn / rifle.tscn / pistol.tscn 实测值，换算到武器局部空间）---
        mount = Vector((0.35, -0.30, -0.50))          # Camera3D/WeaponMount 平移
        if stem == "em68a":
            wp_off, wp_scale = Vector((0.0, 0.02, 0.12)), 1.0
        else:
            wp_off, wp_scale = Vector((0.0, 0.03, 0.04)), 0.4
        cam_local = -(wp_off + mount) / wp_scale
        extra = [("fp_true", gltf_to_blender(cam_local),
                  gltf_to_blender(cam_local + Vector((0.0, 0.0, -1.0))), 75.0)]
        # --- 建议挂载（报告里的提案）：把武器实例左移/上移，使握把与双手进入 75° 视野 ---
        wp_sugg = Vector((-0.25, 0.24, -0.05))
        cam_sugg = -(wp_sugg + mount) / wp_scale
        extra.append(("fp_suggested", gltf_to_blender(cam_sugg),
                      gltf_to_blender(cam_sugg + Vector((0.0, 0.0, -1.0))), 75.0))
        # --- 调姿用特写：右后方 3/4 看握把与右手（不用于交付图） ---
        gp = cfg["grip_look"]
        hs = cfg["hand_scale"]
        eye = Vector((gp[0] + 0.36 * hs, gp[1] + 0.16 * hs, gp[2] + 0.34 * hs))
        extra.append(("grip34", gltf_to_blender(eye), gltf_to_blender(gp), 55.0))
        # 反面检查（从武器左侧看，确认手指没有从握把另一侧穿出）
        eye2 = Vector((gp[0] - 0.30 * hs, gp[1] + 0.10 * hs, gp[2] + 0.26 * hs))
        extra.append(("far34", gltf_to_blender(eye2), gltf_to_blender(gp), 55.0))
        shots = render_views(stem, RENDER_DIR, focus, ortho, extra=extra)
        log("renders: %s" % shots)
        if "--arms-only" in sys.argv:
            for w in wobj_copy:
                w.hide_render = True
            shots2 = render_views(stem, RENDER_DIR, focus, ortho * 0.62,
                                  extra=[("arms34", (focus[0] + 0.9, focus[1] - 0.25, focus[2] + 0.1),
                                                      focus, 55.0)])
            log("arms-only renders: %s" % shots2)

    export_glb(out_glb, arm_objs)
    out_info = gltf_images(out_glb)
    w_sha_after = sha256(weapon_path)
    assert w_sha_after == w_sha_before, "武器 GLB 被改动！"

    report = {
        "stem": stem,
        "weapon": os.path.basename(weapon_path),
        "weapon_sha256_before": w_sha_before,
        "weapon_sha256_after": w_sha_after,
        "weapon_unchanged": w_sha_after == w_sha_before,
        "hand_scale": cfg["hand_scale"],
        "output": os.path.basename(out_glb),
        "output_bytes": os.path.getsize(out_glb),
        "output_sha256": sha256(out_glb),
        "objects": [{"name": o.name, "tris": tris[o.name], "verts": len(o.data.vertices)}
                    for o in arm_objs],
        "tris_per_arm": per_arm,
        "tri_budget": TRI_BUDGET_PER_ARM,
        "penetration": pen,
        "gltf": out_info,
        "pose": key,
    }
    os.makedirs(OUT_DIR, exist_ok=True)
    with open(os.path.join(OUT_DIR, "arms_%s.json" % stem), "w", encoding="utf-8") as fh:
        json.dump(report, fh, ensure_ascii=False, indent=1)
    log("exported %s (%d B) sha256=%s" % (out_glb, report["output_bytes"], report["output_sha256"]))
    log("wrote out/arms_%s.json" % stem)
    return report


def main():
    argv = sys.argv
    argv = argv[argv.index("--") + 1:] if "--" in argv else []
    stems = [a for a in argv if a in PARAMS] or ["em68a", "em57p"]
    do_render = "--render" in argv
    reports = []
    for stem in stems:
        reports.append(run(stem, do_render=do_render))
    log("DONE %s" % [r["stem"] for r in reports])


if __name__ == "__main__":
    main()
