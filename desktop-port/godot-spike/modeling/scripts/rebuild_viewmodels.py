"""rebuild_viewmodels.py — 一条命令重出两把枪的 viewmodel（W9 第 17 号单）。

用途
    把 `em68a_viewmodel.glb` / `em57p_viewmodel.glb` 从源 GLB 重新跑一遍完整管线
    （拆分 + 弹匣枢轴原点迁移）并逐个做验收。整单只需执行这一条命令：

        python rebuild_viewmodels.py                  # 两把枪、全部步骤
        python rebuild_viewmodels.py -- em57p         # 只重出一把

    每把枪的步骤：
      pipeline  跑 Blender 管线生成 viewmodel（脚本内已含枢轴迁移 + 世界空间守恒自检）
      idem      同一管线再跑一次到临时文件，比对 sha256（证明脚本幂等），随后删除临时文件
      verify    跑独立校验器 verify_glb_identity.py（迁移前备份 vs 新出），产出
                `verify_glb_identity_pivot_<stem>.json`（含"世界空间位置守恒"断言）

    `--steps` 可以把步骤拆开单独执行（仅用于单次调用时长受限的环境，例如 DSH 的
    godot_run_headless 约 130 s 上限；默认值 all 即派单要求的一条命令跑完）：

        python rebuild_viewmodels.py -- em68a --steps pipeline
        python rebuild_viewmodels.py -- em68a --steps idem
        python rebuild_viewmodels.py -- em68a --steps verify

状态累积
    每次执行都会把结果合并进 `em-weapons/pivot_rebuild_summary.json`，因此分步执行也能得到
    完整体检报告；总结果在看门狗字段齐全后才会判 PASS。
"""

import hashlib
import json
import os
import shutil
import subprocess
import sys
import time

BLENDER_DEFAULT = r"D:\steam\steamapps\common\Blender\blender.exe"

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", "..", ".."))
WEAP = os.path.join(REPO, "desktop-port", "godot-spike", "modeling", "em-weapons")
WP = os.path.join(HERE, "weapon_postprocess.py")
VERIFY = os.path.join(HERE, "verify_glb_identity.py")
SUMMARY = os.path.join(WEAP, "pivot_rebuild_summary.json")
LOG_PATH = os.path.join(WEAP, "pivot_rebuild.log")

STEMS = ("em68a", "em57p")
ALL_STEPS = ("pipeline", "idem", "verify")


class _Tee(object):
    """把 stdout 同时写进日志文件——整单跑一次可能超过 2 分钟，需要事后可查。"""

    def __init__(self, path):
        self.fh = open(path, "a", encoding="utf-8")

    def write(self, s):
        sys.__stdout__.write(s)
        sys.__stdout__.flush()
        self.fh.write(s)
        self.fh.flush()

    def flush(self):
        sys.__stdout__.flush()
        self.fh.flush()


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def run(cmd, cwd, timeout):
    t0 = time.time()
    proc = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True,
                          encoding="utf-8", errors="replace", timeout=timeout)
    return {
        "cmd": " ".join(cmd),
        "returncode": proc.returncode,
        "seconds": round(time.time() - t0, 2),
        "stdout": proc.stdout or "",
        "stderr": proc.stderr or "",
    }


def tail(text, n=8):
    lines = [ln for ln in text.splitlines() if ln.strip()]
    return "\n".join(lines[-n:])


def paths_for(stem):
    return {
        "source": os.path.join(WEAP, "%s.glb" % stem),
        "output": os.path.join(WEAP, "%s_viewmodel.glb" % stem),
        "backup": os.path.join(WEAP, "%s_viewmodel.pre_pivot_backup.glb" % stem),
        "report": os.path.join(WEAP, "weapon_postprocess_report_%s.json" % stem),
        "verify_json": os.path.join(WEAP, "verify_glb_identity_pivot_%s.json" % stem),
        "idem_output": os.path.join(WEAP, "%s_viewmodel.idem_check.glb" % stem),
        "idem_report": os.path.join(WEAP, "weapon_postprocess_report_%s.idem.json" % stem),
    }


def load_summary():
    if os.path.isfile(SUMMARY):
        try:
            with open(SUMMARY, "r", encoding="utf-8") as fh:
                return json.load(fh)
        except (OSError, ValueError):
            pass
    return {"blender": None, "python": sys.executable, "guns": {}}


def save_summary(summary, blender):
    summary["blender"] = blender
    summary["python"] = sys.executable
    summary["updated_at"] = time.strftime("%Y-%m-%dT%H:%M:%S%z")
    # 总结果：以"每把枪的关键看门狗字段都在且为真"为准，分步执行时也会自动收敛
    ok = bool(summary["guns"])
    for stem, gun in summary["guns"].items():
        gun_ok = (gun.get("pipeline_verdict") == "PASS"
                  and gun.get("idempotent") is True
                  and gun.get("verify_ok_for_pivot") is True
                  and gun.get("world_spatial_ok") is True)
        gun["ok"] = gun_ok
        ok = ok and gun_ok
    summary["ok"] = ok
    os.makedirs(os.path.dirname(SUMMARY), exist_ok=True)
    with open(SUMMARY, "w", encoding="utf-8") as fh:
        json.dump(summary, fh, ensure_ascii=False, indent=1)
    return ok


def ensure_backup(gun, p):
    """迁移前基线：只在缺失时从现有 viewmodel 复制，绝不覆盖，保证对比基准稳定。"""
    if os.path.isfile(p["backup"]):
        gun["backup_reused"] = True
    else:
        if not os.path.isfile(p["output"]):
            raise RuntimeError("既无备份也无现有 viewmodel：%s" % p["output"])
        shutil.copy2(p["output"], p["backup"])
        gun["backup_reused"] = False
        print("  备份基线 -> %s" % os.path.basename(p["backup"]), flush=True)
    gun["baseline_bytes"] = os.path.getsize(p["backup"])
    gun["baseline_sha256"] = sha256(p["backup"])


def step_pipeline(stem, gun, blender, p):
    ensure_backup(gun, p)
    r = run([blender, "-b", "--factory-startup", "--python-exit-code", "1",
             "--python", WP, "--", p["source"], p["output"], p["report"]],
            cwd=WEAP, timeout=900)
    gun["pipeline_rc"] = r["returncode"]
    gun["pipeline_seconds"] = r["seconds"]
    print("  管线 rc=%d（%.1fs）" % (r["returncode"], r["seconds"]), flush=True)
    if r["returncode"] != 0:
        gun["pipeline_tail"] = tail(r["stdout"] + r["stderr"], 20)
        print(gun["pipeline_tail"], flush=True)
        gun.pop("pipeline_verdict", None)
        return False
    gun["output_bytes"] = os.path.getsize(p["output"])
    gun["output_sha256"] = sha256(p["output"])
    if os.path.isfile(p["report"]):
        with open(p["report"], "r", encoding="utf-8") as fh:
            rj = json.load(fh)
        gun["pipeline_verdict"] = rj.get("verdict")
        gun["pivot"] = rj.get("pivot")
        if rj.get("pivot"):
            pv = rj["pivot"]
            print("  报告 verdict=%s 原点 %s → %s 世界最大偏差=%.3e m"
                  % (rj.get("verdict"), pv["origin_before"], pv["origin_after"],
                     pv["world_geometry_max_abs_delta_m"]), flush=True)
    return gun.get("pipeline_verdict") == "PASS"


def step_idem(stem, gun, blender, p):
    r = run([blender, "-b", "--factory-startup", "--python-exit-code", "1",
             "--python", WP, "--", p["source"], p["idem_output"], p["idem_report"]],
            cwd=WEAP, timeout=900)
    if r["returncode"] == 0 and os.path.isfile(p["idem_output"]):
        gun["idempotent_sha256"] = sha256(p["idem_output"])
        gun["idempotent"] = gun["idempotent_sha256"] == gun.get("output_sha256")
        os.remove(p["idem_output"])
    else:
        gun["idempotent"] = False
        gun["idempotent_tail"] = tail(r["stdout"] + r["stderr"], 20)
    if os.path.isfile(p["idem_report"]):
        os.remove(p["idem_report"])
    print("  幂等（两次运行 sha256 相同）=%s" % gun["idempotent"], flush=True)
    return bool(gun["idempotent"])


def step_verify(stem, gun, p):
    r = run([sys.executable, VERIFY, p["backup"], p["output"], p["verify_json"]],
            cwd=WEAP, timeout=600)
    print(tail(r["stdout"], 8), flush=True)
    if not os.path.isfile(p["verify_json"]):
        gun["verify_ok_for_pivot"] = False
        return False
    with open(p["verify_json"], "r", encoding="utf-8") as fh:
        vj = json.load(fh)
    checks = vj.get("checks", [])
    gun["verify_failed_checks"] = [c["check"] for c in checks if not c.get("pass")]
    gun["verify_verdict"] = vj.get("verdict")
    gun["world_spatial_ok"] = next(
        (c["pass"] for c in checks if c["check"].startswith("世界空间位置守恒")), None)
    names_i = vj.get("input", {}).get("structural", {}).get("node_names")
    names_o = vj.get("output", {}).get("structural", {}).get("node_names")
    gun["node_names_i"] = names_i
    gun["node_names_o"] = names_o
    gun["node_world_translation_in"] = vj.get("input", {}).get("node_world_translation")
    gun["node_world_translation_out"] = vj.get("output", {}).get("node_world_translation")
    gun["verify_ok_for_pivot"] = bool(gun["world_spatial_ok"] is True and names_i == names_o)
    # 本单对比的是「迁移前 viewmodel vs 迁移后 viewmodel」：**局部坐标类**断言必然失败
    # （原点迁移的就是对象的局部原点，局部 POSITION/TEXCOORD/法线量化哈希都会变），
    # 而权威断言是"世界空间位置守恒"。这里把失败项按此分类，避免误读成回归。
    local_space_markers = ("POSITION", "TEXCOORD", "NORMAL", "法线", "三角面集合",
                           "三角面绕序", "属性顶点数")
    local_fails = [c for c in gun["verify_failed_checks"]
                   if any(m in c for m in local_space_markers)]
    other_fails = [c for c in gun["verify_failed_checks"] if c not in local_fails]
    gun["verify_failures_local_space_only"] = bool(gun["verify_failed_checks"]) and not other_fails
    gun["verify_other_failures"] = other_fails
    print("  校验：verdict=%s 世界空间守恒=%s 对象名一致=%s"
          % (gun["verify_verdict"], gun["world_spatial_ok"], names_i == names_o), flush=True)
    print("  未通过项=%s" % gun["verify_failed_checks"], flush=True)
    print("  其中局部坐标类=%s 其他=%s（局部坐标变化是本单的目的，权威断言是世界空间守恒）"
          % (local_fails, other_fails), flush=True)
    print("  节点世界平移 输入=%s" % gun["node_world_translation_in"], flush=True)
    print("  节点世界平移 输出=%s" % gun["node_world_translation_out"], flush=True)
    return bool(gun["verify_ok_for_pivot"])


def parse_args(argv):
    if "--" in argv:
        argv = argv[argv.index("--") + 1:]
    else:
        argv = []
    stems = []
    steps = list(ALL_STEPS)
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--steps":
            steps = argv[i + 1].split(",") if i + 1 < len(argv) else list(ALL_STEPS)
            i += 2
            continue
        if a.startswith("--steps="):
            steps = a.split("=", 1)[1].split(",")
            i += 1
            continue
        if not a.startswith("-"):
            stems.append(a)
        i += 1
    bad = [s for s in steps if s not in ALL_STEPS]
    if bad:
        raise SystemExit("未知步骤 %s（可选 %s）" % (bad, list(ALL_STEPS)))
    return (stems or list(STEMS)), steps


def main(argv):
    sys.stdout = _Tee(LOG_PATH)
    stems, steps = parse_args(argv)
    blender = os.environ.get("BLENDER_EXE", BLENDER_DEFAULT)
    if not os.path.isfile(blender):
        print("FAIL: 找不到 Blender: %s" % blender)
        return 1

    summary = load_summary()
    summary.setdefault("guns", {})
    print("=" * 78)
    print("步骤=%s 目标=%s 时间=%s" % (",".join(steps), ",".join(stems),
                                   time.strftime("%Y-%m-%d %H:%M:%S")), flush=True)

    for stem in stems:
        p = paths_for(stem)
        gun = summary["guns"].setdefault(stem, {})
        gun.update({k: v for k, v in p.items() if k in
                    ("source", "output", "backup", "report", "verify_json")})
        print("-" * 78)
        print("[%s] 开始（步骤 %s）" % (stem, ",".join(steps)), flush=True)
        if not os.path.isfile(p["source"]):
            print("FAIL: 缺少源文件 %s" % p["source"], flush=True)
            gun["error"] = "missing source"
            continue
        for step in steps:
            try:
                if step == "pipeline":
                    step_pipeline(stem, gun, blender, p)
                elif step == "idem":
                    if not gun.get("output_sha256") and os.path.isfile(p["output"]):
                        gun["output_sha256"] = sha256(p["output"])
                        gun["output_bytes"] = os.path.getsize(p["output"])
                    step_idem(stem, gun, blender, p)
                elif step == "verify":
                    step_verify(stem, gun, p)
            except Exception as exc:  # noqa: BLE001 —— 单步异常不应中断整批
                gun["%s_error" % step] = "%s: %s" % (type(exc).__name__, exc)
                print("  步骤 %s 异常：%s: %s" % (step, type(exc).__name__, exc), flush=True)

    ok = save_summary(summary, blender)
    print("=" * 78)
    print("汇总 -> %s" % SUMMARY)
    for stem in stems:
        gun = summary["guns"].get(stem, {})
        print("[%s] pipeline=%s idempotent=%s 世界空间守恒=%s verify_ok=%s"
              % (stem, gun.get("pipeline_verdict"), gun.get("idempotent"),
                 gun.get("world_spatial_ok"), gun.get("verify_ok_for_pivot")), flush=True)
    print("总结果: %s" % ("PASS" if ok else "FAIL"), flush=True)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
