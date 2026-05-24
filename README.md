# 任务板 — 桌面日历任务板

一款嵌入桌面的玻璃风格任务 & 日记管理应用，支持 macOS 和 Windows。

## 📥 下载

**[→ 前往 Release 页面下载](https://github.com/ayuan243/taskboard/releases/latest)**

| 系统 | 文件 | 说明 |
|------|------|------|
| Windows | `任务板-3.0.0-Windows.exe` | 免安装，双击直接运行 |
| macOS | `任务板-3.0.0-macOS.dmg` | 支持 Intel + Apple Silicon |

### macOS 安装

1. 下载 `.dmg` 文件
2. 双击打开，把**任务板**拖入 Applications 文件夹
3. 首次打开需右键 → 打开（绕过 Gatekeeper）

### Windows 安装

1. 下载 `.exe` 文件
2. 双击直接运行，无需安装
3. 如弹出安全提示，点击「更多信息」→「仍要运行」

---

## ✨ 功能

- 📅 **3×3 九宫格日历** — 每格可写任务清单 & 日记
- 🎨 **自动配色** — 每个日期自动分配独特的小清新配色
- 🖌 **外观自定义** — 每格可单独设置背景图片/颜色、字体、文字大小、文字颜色
- ⭐ **全局喜好设置** — 一次设定默认字体/颜色/背景，全部格子继承
- 📌 **固定桌面 / 浮动切换**（macOS）— 沉入桌面壁纸层或浮在所有窗口之上
- ↔ **拖动缩放** — 拖动窗口右侧 / 底部边缘自由调整大小
- 📆 **Apple 日历双向同步**（macOS）— 读取系统日历事件 / 推送任务和日记到 Apple 日历
- 💾 **本地存储** — 数据保存在设备本地，无需账号，无需联网

---

## 🛠 从源码构建

### macOS 原生版（Swift）

需要 macOS + Xcode 命令行工具：

```bash
cd taskboard-src
chmod +x build.sh
./build.sh
```

构建完成后 `~/Desktop/任务板.app` 即可运行。

### 跨平台版（Electron，同时支持 macOS & Windows）

需要 Node.js 18+：

```bash
npm install
npm run build        # 同时打包 macOS DMG 和 Windows EXE
npm run build:mac    # 仅 macOS
npm run build:win    # 仅 Windows
```

输出在 `dist/` 目录。

---

## 文件结构

```
日历任务板.html        主应用（HTML + CSS + JS，全平台通用）
electron/
  main.js             Electron 主进程
  preload.js          渲染进程桥接
taskboard-src/
  main.swift          macOS 原生壳（Swift + WKWebView）
  build.sh            一键构建脚本
  make_icon.py        图标生成脚本
```
