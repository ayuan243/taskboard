# 任务板 — 桌面日历任务板

一款嵌入 macOS 桌面的玻璃风格任务 & 日记管理应用。

## 功能

- 📅 3×3 九宫格日历，每格可写任务 & 日记
- 🎨 每日自动不同颜色，支持自定义背景/字体/颜色
- ⭐ 全局喜好设置（默认字体、颜色、背景）
- 📌 固定到桌面 / 浮动模式切换
- ↔ 拖动窗口边缘自由缩放
- 💾 数据保存在本地 localStorage

## 文件结构

```
日历任务板.html        主应用（HTML + CSS + JS）
taskboard-src/
  main.swift          macOS 原生壳（Swift + WKWebView）
  build.sh            一键构建脚本
  make_icon.py        图标生成脚本
```

## 构建

需要 macOS + Xcode 命令行工具：

```bash
cd taskboard-src
chmod +x build.sh
./build.sh
```

构建完成后 `~/Desktop/任务板.app` 即可双击运行。
