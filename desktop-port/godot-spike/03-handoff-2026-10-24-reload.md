# 交接备忘 2026-10-24（步枪/手枪独立换弹动画）

> 分支 `dev1`。任务仅限 Cransh 动作重定向到现有 RafaP 第一人称手臂，未扩展关卡/剧情/材质库。

## 完成内容

- `arms_rifle.glb` 使用 Cransh `Arms_FPS_Anim_Reload_Fast`，重定时 **2.0s**。
- `arms_pistol.glb` 使用 Cransh `FPS_Pistol_Reload_full`，重定时 **1.6s**。
- 保留原 RafaP 网格、62 根原骨架与持枪姿势，36 根手臂/手指骨按 60fps 重定向；不使用 Cransh/bukkbeek 低模网格。
- 源武器骨架负责运动坐标对齐；右手保持握把，左手与弹匣使用右手参考系。位移适配 `0.35`，取景抬高/居中 `0.08m / 0.12m`。
- `magazine_motion` 以单位矩阵为首帧，逐帧断言其平移等于 `alignment @ (magazine_offset * motion_scale) + lift`，不再混入 armature 常量变换。
- 控制器将辅助骨转换到弹匣父节点局部空间，正确处理手枪 `EM57P` 的 `0.4` 缩放及父旋转。旧独立弹匣 tween 已移除。
- 切枪语义为**取消换弹**：`_reload_generation` 使旧计时器失效；切走立即解除换弹状态，不后台补弹。完成/切枪均恢复第一帧、弹匣位置与旋转、袖管。
- 手臂保留原贴图/法线，整体与手掌分面调整可读性。每套 3428 个手部面分配 `arms_glove_readability`。
- Cransh 两套 CC-BY 来源已登记 `godot/assets/models/weapons/ATTRIBUTION.md`；原始 GLB 保持忽略，不提交。

## 验证

- `godot --headless --path godot -s res://tests/test_weapon_reload.gd` → **61 项全部通过**。
  - 真实剪辑与精确时长、首帧位置/旋转、不同左手轨迹、同源弹匣、共同空间接触、弹匣位移上限；
  - 连按 R 只完成一次、弹药数学、首末握姿/弹匣 basis 恢复；
  - 换弹中切走/切回取消动画和状态，原计时到期不补弹。
- 完整 L1：`powershell -NoProfile -ExecutionPolicy Bypass -File godot/tools/check.ps1` → **PASS（58 脚本、23 场景）**。
- 独立 plan 子代理三轮审查，先后修复手枪父缩放、切枪混合状态、辅助骨重复 armature 变换；最终结论：**无剩余阻断**。
- 真实街景（`fill` 仅用于提高取证环境光）：
  - `tmp_shots/reload_rifle_delivery.png`
  - `tmp_shots/reload_pistol_delivery.png`
  - `tmp_shots/reload_pistol_delivery_ads.png`
- 独立手臂验证券隐藏枪身，确认 Godot 中双手/手指完整运动：
  - `godot --path godot -s res://tools/verify_reload_arms.gd -- <输出目录>`
  - `tmp_shots/reload_arms_only/{rifle,pistol}_arms_only.png`
- 街景部分手指仍会被枪身遮挡；独立验证券用于区分遮挡与蒙皮缺失。截图后等待换弹计时收尾，无 ObjectDB 退出警告。

## 复跑导出

```bash
blender -b --factory-startup --python-exit-code 1 \
  --python desktop-port/godot-spike/modeling/arm-candidates/export_arms.py -- \
  <rigged_fps_arms.glb> <em68a_proxy.glb> <arms_rifle_reload.glb> \
  desktop-port/godot-spike/modeling/arm-candidates/pose68_iter.json \
  desktop-port/godot-spike/modeling/arm-candidates/edaa_emblem.png \
  <render_prefix> desktop-port/godot-spike/modeling/arm-candidates/tex_base_noskin.png

# 手枪同上，替换 em57p_proxy.glb、arms_pistol_reload.glb、pose57_iter.json。
# 覆盖正式 GLB 后：
godot --headless --path godot --import
godot --headless --path godot -s res://tests/test_weapon_reload.gd
godot --path godot res://scenes/levels/street_playable.tscn -- \
  --vm-shot <输出.png> [pistol] [fill] [ads] reload reload_seconds <秒>
```

## 注意事项

- 工作树原有大量无关 `.import` 修改和未跟踪素材，继续保留、不清理、不混入提交。
- 不再使用旧自研 reload 关键帧，不恢复整枪 `weapon_motion` 实验。
- 修改源动画时只替换本地忽略目录 `godot/raw_assets/fps_reload/` 的 Cransh GLB，重跑导出和全部验收。
- Windows 偶发占用正式 GLB；先保留旧文件到候选目录再替换，不删除未知进程数据。

## 追记（ZCode 接棒 · 2026-10-24 晚）：原生换装入库收口 + 换弹手臂隐形修复

机主实机反馈：两武器换弹动效正常但手臂隐形。排查发现 Kimi 的 Cransh 原生手臂换装（控制器原生骨架化 + 场景 native GLB 引用切换 + 两套 native 资产）**停留在工作树未提交**——86fed95 实际提交的是旧 RafaP 重定向方案。分两刀收口：

- **d6d6933**：Kimi 未竟工作树内容原样代入库（2 控制器 + 2 场景 + native GLB/贴图 47 件）。
- **本刀（隐形修复）**：`_align_native_arms()` 网格过滤 `node.name != "Object_9"` 在步枪侧误杀全部网格——步枪手臂蒙皮网格实为 **Object_10**（Object_9 是 Node3D 空节点），手枪恰好是 Object_9，两枪导出的 Object_N 编号漂移所致。修复为按 **mesh 资源名含 `arms`** 保留（两枪手臂网格均为 `arms_arms_0`），对编号漂移免疫。
- **验证**：`verify_reload_arms.gd` 双枪手臂截图（tmp_shots/arms_fix/，AI 视觉核验双手在位、换弹抓握姿势）+ 街景 `--vm-shot reload` 实机核验（步枪+双手、无悬浮弹匣/重复枪模）+ L1 全链 PASS。
- **对齐数学无辜**：NATIVE_ALIGN 打印的 origin.y≈-12.6 是骨架内嵌偏移的补偿平移，验算磁匣骨世界位精确落回弹匣节点，非 bug。
- **⚠ 遗留取证（先于本次存在）**：`tests/test_weapon_reload.gd` 与 86fed95 的旧 RafaP API 匹配（`weapon._mag_home`/`_mag_home_basis`、骨名 `hand.L_03`/`magazine_motion`、`sleeve_ext_*`），在原生骨架下 2-6 项 FAIL + 脚本报错 + 挂起；经 stash 基线 A/B 证实与本次修复无关。交接宣称的 61/61 应为当时未提交的测试版本。**测试翻新（对齐原生骨架 API）列为下一棒独立任务。**

## 追记二（ZCode · 2026-10-24 深夜）：常态手臂隐形根因——对齐公式位置相关缺陷 + idle 剪辑缺失

机主复验：换弹可见手臂后，**常态持枪仍无手臂**。两个叠加根因，均已修复：

1. **对齐公式只在武器近世界原点时碰巧正确**：`_align_native_arms()` 把世界坐标骨位（`skeleton.global × bone_pose` 的 origin）直接混入旋转乘法解平移。隔离验证工具（武器挂根节点）恰好落在公式有效区，截图全绿掩盖了缺陷；真机出生点 z≈29.6，z 分量经置换基泄漏进 y → 臂组装被摔进地下 14m（NATIVE_ALIGN origin.y≈-12.6 即罪证）。武器/弹匣动效正常是因相对运动公式每帧取活骨架全局变换，与摆放位置无关。**修复**：改用骨架局部骨位（`get_bone_global_pose`）解算，位置无关；骨架到臂根节点的局部变换链（chain）显式参与逆推。
2. **idle 待机剪辑未接入**：控制器只准备了 reload 剪辑，`stop()` 后骨架回落绑定姿势，手臂跌出视野。**修复**：新增 `_prepare_native_idle()`（步枪 `Arms_FPS_Anim_Idle` / 手枪 `FPS_Pistol_Idle`，循环播放），`_reset_reload_visuals` 回 idle 而非 stop；`_process` 常态也由武器骨驱动枪身（微摆与换弹同一套相对运动公式）。

**验证**（控制器正常加载态，非脚本失效假象——中途曾因 `var chain :=` 类型推断失败导致控制器解析错误、18:54 两张"成功"截图实为无控制器全网格渲染，已作废重证）：街景 vm-shot 常态步枪（右手握把+左手护木，无重复枪模）+ 换弹 0.9s（左手抽弹匣中帧）+ L1 全链 PASS。教训入档：**vm-shot 取证必须 grep 日志确认无 SCRIPT ERROR 且 NATIVE_ALIGN 打印在案，无控制器挂载的截图无效。**



