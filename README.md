# Video2Mp3 纪

macOS 桌面应用，用于选择一个根目录，递归扫描视频文件，并在视频所在目录提取同名 `mp3`。也支持切换到纯 MP3 播放模式，直接播放目录里已有的 MP3。

## 功能

- 递归扫描常见视频格式：`mp4`、`mov`、`mkv`、`avi`、`webm` 等。
- 支持单选、多选、全选和清空选择。
- 支持 4、6、8 并发转换。
- 显示单任务和总体转换进度百分比。
- 显示每个视频和 MP3 的文件大小，并汇总视频总大小和 MP3 总大小。
- 自动记住最近打开的根目录。
- 已成功生成的 `mp3` 会在下次启动时跳过。
- 可选择转换成功后删除源视频。
- 表格内支持 `Space` 播放视频、`Ctrl+Space` 播放生成的 MP3。
- 支持“转换模式 / MP3 播放 / 音乐调音”切换；MP3 播放模式会递归扫描目录中的 `.mp3` 文件。
- MP3 播放模式按列表顺序播放，支持上一首、下一首、暂停、继续、前进/后退 5 秒、前进/后退 30 秒。
- MP3 播放模式会记住每个根目录上次播放到哪一首和哪一秒，下次启动后可继续播放。
- 音乐调音支持 Rubber Band 变调；可先用 Demucs 高质量分离人声和背景音，再选择只导出分离结果或继续对选中音轨调音，调音模块导出 MP3 使用 320k 编码。
- 可扫描并确认删除包含 `.mp4.part` 未完成下载文件的文件夹。
- 转换过程有结构化日志，便于定位问题。
- 打包脚本会生成图标、`.app`、zip 包，并更新到 `/Applications`。

## 构建

```bash
./scripts/build_release.sh
```

产物：

- `dist/Video2Mp3 纪.app`
- `dist/Video2Mp3 纪.zip`
- `/Applications/Video2Mp3 纪.app`

## 依赖

基础转换需要本机安装 `ffmpeg`：

```bash
brew install ffmpeg
```

音乐调音需要安装 `rubberband`：

```bash
brew install rubberband
```

如果要在调音前分离“人声 / 背景音”，还需要安装 Demucs：

```bash
pipx install demucs
# 或：
python3 -m pip install -U demucs
```

## 文档

中文设计、使用、测试和数据流说明位于 `local_docs/`。
