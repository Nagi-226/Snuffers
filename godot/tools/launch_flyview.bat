@echo off
rem ============================================================
rem launch_flyview.bat — 一键打开街区开发效果飞行视角
rem 场景: c1m1_oldtown_south（street_test.tscn，自由飞行相机）
rem 引擎路径如有变化改下面 GODOT_EXE 一行即可
rem ============================================================
set "GODOT_EXE=D:\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64.exe"
set "PROJECT_DIR=%~dp0.."
set "SCENE=res://scenes/levels/street_test.tscn"

echo ============================================
echo  Snuffers 开发效果预览 - 自由飞行视角
echo  场景: %SCENE%
echo --------------------------------------------
echo  操作: 点击画面捕获鼠标 ^| 鼠标移动转视角
echo        WASD 平移 ^| Q/E 升降 ^| Shift 加速
echo        Esc 释放鼠标 ^| 直接关窗退出
echo ============================================

if not exist "%GODOT_EXE%" (
    echo [错误] 找不到引擎: %GODOT_EXE%
    echo 请编辑本文件修正 GODOT_EXE 路径。
    pause
    exit /b 1
)

start "" "%GODOT_EXE%" --path "%PROJECT_DIR%" "%SCENE%"
