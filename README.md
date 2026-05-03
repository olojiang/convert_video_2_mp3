# Convert Video 2 MP3

macOS 桌面应用，用于选择一个根目录，递归扫描视频文件，并在视频所在目录提取同名 `mp3`。

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
- 可扫描并确认删除包含 `.mp4.part` 未完成下载文件的文件夹。
- 转换过程有结构化日志，便于定位问题。
- 打包脚本会生成图标、`.app`、zip 包，并更新到 `/Applications`。

## 构建

```bash
./scripts/build_release.sh
```

产物：

- `dist/ConvertVideo2MP3.app`
- `dist/ConvertVideo2MP3.zip`
- `/Applications/ConvertVideo2MP3.app`

## 依赖

需要本机安装 `ffmpeg`：

```bash
brew install ffmpeg
```

## 文档

中文设计、使用、测试和数据流说明位于 `local_docs/`。
