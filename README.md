# 轻刷题

一款适合在桌面空闲时快速刷题的轻量级软件。当前版本为 macOS 原生应用，使用 Swift、AppKit、PDFKit 和 Carbon 开发，无第三方依赖，可完全离线运行。

## 特点

- 管理页与悬浮答题页分离，答题时可只保留精简面板。
- 支持导入“题目 PDF + 答案解析 PDF”并自动识别题干、选项、答案和解析。
- 支持逐题判定和整卷判定，整卷结束后提供得分、题号导航和逐题回顾。
- 支持选题范围、随机顺序、只做错题和从头重做。
- 错题永久保存，只有在管理页主动删除时才会移出错题集。
- 按选定试卷记录上次得分、最高得分和作答次数，每题 1 分。
- 显示言语、常识、数量、判断和资料五个模块的首次作答正确率，重做不会改写统计。
- 整卷计时、超时提示、断点续做和已用时间恢复；可设置缩成小球时暂停计时。
- 答题页可自由调整宽高，长文字只在当前宽度内换行，不会反向撑宽窗口。
- 可设置背景透明度、统一文字颜色和字号；背景可完全透明，文字和图片仍保持不透明。
- 鼠标移出时可缩成 20×20 无字小圆球，移入小球恢复原位置。
- 全局快捷键：`Command + Option + Q` 显示/隐藏，`Command + Option + L` 锁定/解除当前显隐状态。

## 运行环境

- macOS 12.0 或更高版本
- Xcode Command Line Tools（需要 `swiftc` 和 `codesign`）

## 构建与启动

```bash
chmod +x build.sh
./build.sh
open "dist/轻刷题.app"
```

数据默认保存在 `~/Library/Application Support/QuickQuiz/`，不会上传到服务器。

## 自检

```bash
dist/轻刷题.app/Contents/MacOS/QuickQuiz --logic-test
dist/轻刷题.app/Contents/MacOS/QuickQuiz --self-test
```

## 即将开发

### 1. Windows 适配

- 提供 Windows 桌面版本和可直接运行的安装包。
- 保留悬浮答题、透明背景、快捷键、缩球和本地持久化等核心体验。
- 抽离可共享的题库数据与作答逻辑，减少 macOS 和 Windows 版本的行为差异。

### 2. 多题库管理

- 支持同时导入、命名、切换和删除多套题库。
- 每个题库独立保存错题、成绩、模块正确率、断点和计时。
- 增加题库列表、题库检索、导入状态和备份/恢复能力。

## 项目结构

```text
Sources/QuickQuiz/   macOS 应用源码
Resources/           内置题库、题目 PDF 和答案解析 PDF
Tools/               题库生成工具
Info.plist           macOS 应用配置
build.sh             本地构建脚本
```
