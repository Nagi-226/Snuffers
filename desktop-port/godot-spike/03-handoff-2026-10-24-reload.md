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
