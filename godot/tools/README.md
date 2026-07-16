# tools/ — L1 校验链与每日构建（W6 质检蜂维护）

## 用法

```powershell
# L1 校验链（从任意目录调用均可，脚本自动定位 godot/ 工程根）
powershell -File godot/tools/check.ps1

# 每日构建（先过 L1，再导出带日期戳的 exe）
powershell -File godot/tools/daily_build.ps1
```

- `check.ps1` 全绿输出 `L1 PASS`（退出码 0）；任一失败输出 `L1 FAIL` + 明细（退出码 1）。
- `daily_build.ps1` 产物：`godot/export/ruins_breakout_spike_yyyyMMdd.exe`（`godot/export/` 已 gitignore），结束打印产物大小与耗时。

## check.ps1 校验步骤

| 步 | 命令 | 目的 |
|----|------|------|
| a | `--headless --import` | 刷新导入缓存 |
| b | `-s tests/check_scripts.gd -- <gds>` | 逐脚本编译校验（排除 `addons/`、`.godot/`），逐文件输出 SCRIPT-OK / SCRIPT-FAIL |
| c | `--headless --quit` | 主场景启动冒烟（读 project.godot 的 main_scene） |
| d | `-s tests/smoke_contracts.gd` | 契约断言（参数值 / 信号 / 状态键） |
| e | `--headless --quit <scene>` | `scenes/**/*.tscn` 逐个实例化冒烟 |

## 已知坑

1. **export preset 名称必须写 `Windows Desktop`**（与 `export_presets.cfg` 的 `name`/`platform` 一致），拼错导出直接失败。
2. **PowerShell 脚本保持纯 ASCII**——注释也只写英文，规避 Windows 控制台 / 文件编码坑（GDScript 与 Markdown 文档不受此限）。
3. **多实例并发 `--import` 会抢 `godot/.godot` 缓存锁**——校验链必须串行执行；蜂后集成时统一串行跑，工蜂并行施工期间遇锁等待 15 秒重试一次。
4. **`-s` 脚本模式下 autoload 不自动实例化**——契约断言 / 编译校验脚本用 `load('res://autoload/xxx.gd').new()` 手动实例化（autoload 常量访问在编译期解析，`game_state.gd` 的 `reset()` 在此模式下可正常工作）。
5. **`--check-only --script` 在 headless 下无法解析 autoload 成员访问**（`Events.*` 信号、`GameConfig.<var>`、`GameState.*` 一律误报 `Identifier not found`；常量访问不受影响）。这是引擎行为，加 `--editor` 或改 res:// 路径均无效。因此步骤 b 改用 `tests/check_scripts.gd` harness：先在 root 下重建三个 autoload 节点，再对每个脚本 `load()` + `reload()` 强制重编译，语义等同逐脚本 `--check-only` 但无误报。
6. **`Godot_v4.6.2-stable_win64.exe` 是 GUI 子系统程序**：PowerShell 的 `&` 调用会异步放行，拿不到输出和退出码（`$LASTEXITCODE` 为空）。两个 ps1 一律走 `System.Diagnostics.Process`（同步等待 + 双管道异步读取防死锁 + 可靠退出码）。
7. `--check-only` 只查编译不跑逻辑；运行时契约问题靠步骤 d 兜住。
