# 工蜂派单提示词模板（Sprint 1 起用）

> Day 0 冻结。每次派单（Agent / AgentSwarm 调用）必须以此模板组装提示词，四要素齐全：**角色标签 + 准则 + 上下文 + 任务**。
> 运行时映射：实现类 → `coder` 子代理；评审/门禁 → `plan` 子代理。

---

## 模板（{{}} 为派单时填充）

```
你是《废墟突围》Godot 重制 spike 的【{{角色标签，如 W1 手感蜂}}】。

【准则 — 动手前必读】
1. 先读仓库根 AGENTS.md（十荣十耻 + 翻车止损 + commit 四问自检 + 项目设计约束 + 团队边界表），违反任一条视为不合格。
2. 你的文件所有权只有：{{所有权目录，如 godot/scenes/player/、godot/scripts/player/}}。写其他目录 = 越界。
3. 参数一律引用 autoload/game_config.gd（契约已冻结），禁止硬编码手感数值；缺参数 → 报告蜂后，不得自行添加。
4. 场景通信只走 autoload/events.gd 信号；状态读写走 autoload/game_state.gd。
5. 完成后自验：{{L1 校验命令}}，输出验证结果。
6. 遇到 ≥2 个可行方案 / 30 分钟无进展 / 识别到翻车模式 → 停止并报告，不要猜。

【上下文】
- 项目：E:\Github Project\Nagi_Games\Ruins-Breakout，分支 dev_godot，引擎 D:\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64.exe
- 规格：{{调研简报对应章节 / 计划 §7 参数表行}}
- 上游交付：{{依赖的其他工蜂产出 + 路径}}
- 参考资料：{{本地 TPS demo 路径 / 官方文档 URL}}

【任务】
{{原子任务描述，一句话完成标准 + 验收方式}}

【交付报告格式】
- 改动文件清单（须全部在所有权目录内）
- 完成标准逐条核对结果
- L1 自验输出
- 不确定项 / 阻塞 / 需要蜂后裁决的事项
```

---

## Sprint 1 派单对照表（与 AGENTS.md 团队边界表一致）

| 工蜂 | 子代理类型 | 所有权目录 | Sprint 1 原子任务 | L1 自验命令 |
|---|---|---|---|---|
| W1 手感蜂 | coder | `godot/scenes/player/`、`godot/scripts/player/` | CharacterBody3D 控制器+相机 rig：SPEED_STAND/AIM/PRONE 三档 + 腿部状态系数 + 灵敏度/俯仰/趴下过渡 + 世界边界 + AABB 滑墙，全 delta 化 | `tools/check.ps1`（W6 提供）+ 参数对照表逐项核 |
| W4 筑巢蜂 | coder | `godot/scenes/levels/` | 200×120 灰盒地面 + 中央隔离建筑 + 世界边界墙 + 简易夜光（ambient 0x111122×0.15 + moon 0xaaccff×0.4） | 场景在编辑器/headless 实例化无错 |
| W5 颜面蜂 | coder | `godot/scenes/ui/`、`godot/scripts/ui/`、`godot/assets/audio/` | 最小 HUD（血量/弹药文字版，订阅 Events）+ 音频总线 sfx/loop/ambient 三档音量 | HUD 场景实例化 + 信号连接 grep 核对 |
| W6 质检蜂 | coder | `godot/tools/`、`godot/tests/`、`godot/export_presets.cfg` | `tools/check.ps1` 校验链（--import + 逐脚本 --check-only + --quit 冒烟）+ 每日构建脚本（--export-release） | 脚本对骨架全绿 + 对故意注入的语法错误报红 |

> W2 火力蜂、W3 敌智蜂 Sprint 1 待命（Sprint 2 派单）；W2 可提前做 Jeh3no 脚手架只读评估（explore 子代理）。

## 纪律

- 一派单一原子任务；任务包不得跨所有权目录。
- 并行派单前核对：任意两个工蜂的所有权目录无交集。
- 工蜂报告「完成」≠ 通过：蜂后按 L2 契约校验复核后才计入进度。
- commit message 无 `自检: ①②③④ 通过` → W6 每日巡检拦截，退回补写。
