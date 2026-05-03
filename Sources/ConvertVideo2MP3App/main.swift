import AppKit
import ConvertCore
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: MainWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        BootstrapLog.write("applicationDidFinishLaunching")
        let controller = MainWindowController()
        windowController = controller
        controller.window?.center()
        controller.window?.makeKeyAndOrderFront(nil)
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

private enum BootstrapLog {
    static func write(_ message: String) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ConvertVideo2MP3-bootstrap.log")
        let line = "\(Date()) \(message)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: url.path),
               let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: url, options: [.atomic])
            }
        }
    }
}

final class KeyHandlingTableView: NSTableView {
    var onSpace: ((Bool) -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 49 {
            onSpace?(event.modifierFlags.contains(.control))
            return
        }
        super.keyDown(with: event)
    }
}

final class MainWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let scanner = VideoScanner()
    private let partFolderCleaner = PartFolderCleaner()
    private let fileSizeReader = FileSizeReader()
    private let historyStore = RootHistoryStore()
    private let logger: FileEventLogger
    private var stateStore: TaskStateStore?
    private var coordinator: ConversionCoordinator?
    private var rootURL: URL?
    private var tasks: [ConversionTask] = []
    private var selectedIDs = Set<String>()
    private var isConverting = false

    private let rootLabel = NSTextField(labelWithString: "未选择目录")
    private let summaryLabel = NSTextField(labelWithString: "请选择一个根目录开始扫描")
    private let logLabel = NSTextField(labelWithString: "")
    private let tableView = KeyHandlingTableView()
    private let scrollView = NSScrollView()
    private let chooseButton = NSButton(title: "选择目录", target: nil, action: nil)
    private let rescanButton = NSButton(title: "重新扫描", target: nil, action: nil)
    private let selectAllButton = NSButton(title: "全选", target: nil, action: nil)
    private let selectNoneButton = NSButton(title: "清空选择", target: nil, action: nil)
    private let startButton = NSButton(title: "开始转 MP3", target: nil, action: nil)
    private let stopButton = NSButton(title: "停止", target: nil, action: nil)
    private let revealLogsButton = NSButton(title: "打开日志", target: nil, action: nil)
    private let cleanPartFoldersButton = NSButton(title: "清理 .mp4.part 文件夹", target: nil, action: nil)
    private let deleteSourceCheckbox = NSButton(checkboxWithTitle: "成功后删除源视频", target: nil, action: nil)
    private let concurrencyPopup = NSPopUpButton()
    private let progressIndicator = NSProgressIndicator()

    init() {
        logger = Self.makeLogger()
        logger.log(.info, event: "app.window_initializing", details: [:])

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1240, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Convert Video 2 MP3"
        window.minSize = NSSize(width: 1040, height: 560)
        super.init(window: window)
        setupUI()
        restoreLastRootIfPossible()
        logger.log(.info, event: "app.window_ready", details: ["log": logger.logURL.path])
    }

    required init?(coder: NSCoder) {
        return nil
    }

    private static func makeLogger() -> FileEventLogger {
        if let logger = try? FileEventLogger(logURL: AppPaths.defaultLogURL()) {
            return logger
        }

        let fallbackURL = FileManager.default.temporaryDirectory.appendingPathComponent("ConvertVideo2MP3.log")
        if let logger = try? FileEventLogger(logURL: fallbackURL) {
            return logger
        }

        fputs("Unable to create ConvertVideo2MP3 log file.\n", stderr)
        exit(1)
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let toolbar = NSStackView(views: [
            chooseButton,
            rescanButton,
            selectAllButton,
            selectNoneButton,
            concurrencyPopup,
            deleteSourceCheckbox,
            startButton,
            stopButton,
            cleanPartFoldersButton,
            revealLogsButton
        ])
        toolbar.orientation = .horizontal
        toolbar.spacing = 8
        toolbar.alignment = .centerY
        toolbar.distribution = .gravityAreas

        concurrencyPopup.addItems(withTitles: ["并发 4", "并发 6", "并发 8"])
        concurrencyPopup.selectItem(withTitle: "并发 4")
        stopButton.isEnabled = false

        rootLabel.lineBreakMode = .byTruncatingMiddle
        summaryLabel.textColor = .secondaryLabelColor
        logLabel.textColor = .secondaryLabelColor
        logLabel.lineBreakMode = .byTruncatingMiddle
        progressIndicator.isIndeterminate = false
        progressIndicator.minValue = 0
        progressIndicator.maxValue = 1

        tableView.dataSource = self
        tableView.delegate = self
        tableView.onSpace = { [weak self] controlPressed in
            self?.playFocusedRow(openMP3: controlPressed)
        }
        tableView.allowsMultipleSelection = true
        tableView.usesAlternatingRowBackgroundColors = true
        addColumn(id: "selected", title: "选择", width: 62)
        addColumn(id: "file", title: "视频文件", width: 330)
        addColumn(id: "status", title: "状态", width: 110)
        addColumn(id: "progress", title: "进度", width: 80)
        addColumn(id: "videoSize", title: "视频大小", width: 100)
        addColumn(id: "mp3Size", title: "MP3大小", width: 100)
        addColumn(id: "output", title: "输出 MP3", width: 310)

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true

        let labels = NSStackView(views: [rootLabel, summaryLabel, logLabel, progressIndicator])
        labels.orientation = .vertical
        labels.spacing = 6
        labels.alignment = .leading
        labels.distribution = .fill

        let main = NSStackView(views: [toolbar, labels, scrollView])
        main.orientation = .vertical
        main.spacing = 12
        main.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        main.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(main)

        NSLayoutConstraint.activate([
            main.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            main.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            main.topAnchor.constraint(equalTo: contentView.topAnchor),
            main.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 360),
            progressIndicator.widthAnchor.constraint(equalTo: main.widthAnchor, constant: -32)
        ])

        chooseButton.target = self
        chooseButton.action = #selector(chooseRoot)
        rescanButton.target = self
        rescanButton.action = #selector(rescan)
        selectAllButton.target = self
        selectAllButton.action = #selector(selectAllTasks)
        selectNoneButton.target = self
        selectNoneButton.action = #selector(clearSelection)
        startButton.target = self
        startButton.action = #selector(startConversion)
        stopButton.target = self
        stopButton.action = #selector(stopConversion)
        revealLogsButton.target = self
        revealLogsButton.action = #selector(revealLogs)
        cleanPartFoldersButton.target = self
        cleanPartFoldersButton.action = #selector(cleanPartFolders)
        deleteSourceCheckbox.target = self
        deleteSourceCheckbox.action = #selector(deleteSourceOptionChanged)

        logLabel.stringValue = "日志文件：\(logger.logURL.path)"
    }

    private func addColumn(id: String, title: String, width: CGFloat) {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
        column.title = title
        column.width = width
        tableView.addTableColumn(column)
    }

    private func restoreLastRootIfPossible() {
        guard let last = historyStore.load().first,
              FileManager.default.fileExists(atPath: last.path) else {
            return
        }
        loadRoot(last)
    }

    @objc private func chooseRoot() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        if panel.runModal() == .OK, let url = panel.url {
            loadRoot(url)
        }
    }

    @objc private func rescan() {
        guard let rootURL else { return }
        loadRoot(rootURL)
    }

    private func loadRoot(_ url: URL) {
        do {
            logger.log(.info, event: "scan.started", details: ["root": url.path])
            rootURL = url
            historyStore.remember(url)
            rootLabel.stringValue = "根目录：\(url.path)"

            let appStateURL = AppPaths.stateURL(for: url)
            stateStore = TaskStateStore(stateURL: appStateURL)
            let videos = try scanner.scan(root: url)
            tasks = try stateStore?.load(for: videos) ?? []
            selectedIDs = Set(tasks.filter { $0.status != .succeeded }.map(\.id))
            try stateStore?.save(tasks)

            logger.log(.info, event: "scan.finished", details: [
                "root": url.path,
                "videos": "\(tasks.count)",
                "selected": "\(selectedIDs.count)"
            ])
            refresh()
        } catch {
            logger.log(.error, event: "scan.failed", details: ["error": error.localizedDescription])
            showError(error)
        }
    }

    @objc private func selectAllTasks() {
        selectedIDs = Set(tasks.map(\.id))
        refresh()
    }

    @objc private func clearSelection() {
        selectedIDs.removeAll()
        refresh()
    }

    @objc private func startConversion() {
        guard !isConverting else { return }
        let selectedTasks = tasks.filter { selectedIDs.contains($0.id) && $0.status != .succeeded }
        guard !selectedTasks.isEmpty else { return }

        isConverting = true
        setControlsForConversion(active: true)
        let concurrency = selectedConcurrency()
        let options = ConversionOptions(deleteSourceOnSuccess: deleteSourceCheckbox.state == .on)
        let currentCoordinator = ConversionCoordinator(
            extractor: FFmpegAudioExtractor(),
            logger: logger,
            onTaskUpdate: { [weak self] task in
                Task { @MainActor in
                    self?.apply(taskUpdate: task)
                }
            }
        )
        coordinator = currentCoordinator

        Task { @MainActor in
            logger.log(.info, event: "ui.conversion_requested", details: [
                "selected": "\(selectedTasks.count)",
                "concurrency": "\(concurrency)",
                "delete_source_on_success": "\(options.deleteSourceOnSuccess)"
            ])
            let converted = await currentCoordinator.convert(tasks: selectedTasks, concurrency: concurrency, options: options)
            merge(converted)
            try? stateStore?.save(tasks)
            isConverting = false
            setControlsForConversion(active: false)
            refresh()
        }
    }

    @objc private func stopConversion() {
        coordinator?.requestStop()
        stopButton.isEnabled = false
        summaryLabel.stringValue = "正在停止：等待当前 ffmpeg 进程结束或被终止"
    }

    @objc private func revealLogs() {
        NSWorkspace.shared.activateFileViewerSelecting([logger.logURL])
    }

    @objc private func cleanPartFolders() {
        guard let rootURL else {
            showMessage(title: "还没有选择根目录", text: "请先选择要扫描的视频根目录。")
            return
        }

        do {
            logger.log(.info, event: "cleanup.part_folders.scan_started", details: ["root": rootURL.path])
            let candidates = try partFolderCleaner.scan(root: rootURL)
            logger.log(.info, event: "cleanup.part_folders.scan_finished", details: [
                "root": rootURL.path,
                "folders": "\(candidates.count)",
                "part_files": "\(candidates.reduce(0) { $0 + $1.partFiles.count })"
            ])

            guard !candidates.isEmpty else {
                showMessage(title: "没有发现可清理文件夹", text: "当前根目录下没有包含 .mp4.part 文件的文件夹。")
                return
            }

            guard confirmDeletingPartFolders(candidates) else {
                logger.log(.info, event: "cleanup.part_folders.cancelled", details: ["folders": "\(candidates.count)"])
                return
            }

            let deleted = try partFolderCleaner.deleteFolders(candidates)
            logger.log(.info, event: "cleanup.part_folders.deleted", details: [
                "root": rootURL.path,
                "folders": "\(deleted)"
            ])
            showMessage(title: "清理完成", text: "已删除 \(deleted) 个包含 .mp4.part 文件的文件夹。")
            loadRoot(rootURL)
        } catch {
            logger.log(.error, event: "cleanup.part_folders.failed", details: [
                "root": rootURL.path,
                "error": error.localizedDescription
            ])
            showError(error)
        }
    }

    private func confirmDeletingPartFolders(_ candidates: [PartFolderCandidate]) -> Bool {
        let preview = candidates
            .prefix(8)
            .map { "• \($0.folderURL.path)" }
            .joined(separator: "\n")
        let suffix = candidates.count > 8 ? "\n… 还有 \(candidates.count - 8) 个文件夹" : ""

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "确认删除 \(candidates.count) 个文件夹？"
        alert.informativeText = "这些文件夹包含 .mp4.part 未完成下载文件，删除会递归移除整个文件夹，不能通过应用撤销。\n\n\(preview)\(suffix)"
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        return alert.runModal() == .alertFirstButtonReturn
    }

    @objc private func deleteSourceOptionChanged() {
        logger.log(.info, event: "ui.delete_source_option_changed", details: [
            "enabled": "\(deleteSourceCheckbox.state == .on)"
        ])
    }

    private func merge(_ converted: [ConversionTask]) {
        var byID = Dictionary(uniqueKeysWithValues: converted.map { ($0.id, $0) })
        for index in tasks.indices {
            if let task = byID.removeValue(forKey: tasks[index].id) {
                tasks[index] = task
            }
        }
    }

    @MainActor private func apply(taskUpdate: ConversionTask) {
        guard let index = tasks.firstIndex(where: { $0.id == taskUpdate.id }) else { return }
        tasks[index] = taskUpdate
        try? stateStore?.save(tasks)
        refresh()
    }

    private func selectedConcurrency() -> Int {
        switch concurrencyPopup.titleOfSelectedItem {
        case "并发 6": return 6
        case "并发 8": return 8
        default: return 4
        }
    }

    private func setControlsForConversion(active: Bool) {
        chooseButton.isEnabled = !active
        rescanButton.isEnabled = !active
        startButton.isEnabled = !active
        stopButton.isEnabled = active
        concurrencyPopup.isEnabled = !active
        deleteSourceCheckbox.isEnabled = !active
        cleanPartFoldersButton.isEnabled = !active
    }

    private func refresh() {
        tableView.reloadData()
        let succeeded = tasks.filter { $0.status == .succeeded }.count
        let failed = tasks.filter { $0.status == .failed }.count
        let cancelled = tasks.filter { $0.status == .cancelled }.count
        let totalProgress = overallProgress()
        let sizeSummary = fileSizeReader.summary(for: tasks)
        summaryLabel.stringValue = "共 \(tasks.count) 个视频，已选择 \(selectedIDs.count)，成功 \(succeeded)，失败 \(failed)，取消 \(cancelled)，总进度 \(Int(totalProgress * 100))%，视频总大小 \(FileSizeText.format(sizeSummary.videoBytes))，MP3总大小 \(FileSizeText.format(sizeSummary.mp3Bytes))"
        progressIndicator.doubleValue = totalProgress
    }

    private func overallProgress() -> Double {
        guard !tasks.isEmpty else { return 0 }
        let total = tasks.reduce(0) { partial, task in
            partial + (task.status == .succeeded ? 1 : task.progress)
        }
        return total / Double(tasks.count)
    }

    private func showError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.runModal()
    }

    private func showMessage(title: String, text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.alertStyle = .informational
        alert.runModal()
    }

    private func playFocusedRow(openMP3: Bool) {
        let row = tableView.selectedRow
        guard row >= 0, row < tasks.count else { return }
        let task = tasks[row]

        if openMP3 {
            guard FileManager.default.fileExists(atPath: task.outputURL.path) else {
                logger.log(.warning, event: "playback.mp3_missing", details: [
                    "source": task.sourceURL.path,
                    "output": task.outputURL.path
                ])
                showMessage(title: "MP3 还不能播放", text: "这个视频还没有转化完成，转化成功后可以用 Ctrl+Space 播放 MP3。")
                return
            }
            logger.log(.info, event: "playback.mp3_opened", details: ["output": task.outputURL.path])
            NSWorkspace.shared.open(task.outputURL)
            return
        }

        guard FileManager.default.fileExists(atPath: task.sourceURL.path) else {
            showMessage(title: "源视频不存在", text: "源视频可能已经在转化成功后被删除。")
            return
        }
        logger.log(.info, event: "playback.video_opened", details: ["source": task.sourceURL.path])
        NSWorkspace.shared.open(task.sourceURL)
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        tasks.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < tasks.count, let id = tableColumn?.identifier.rawValue else { return nil }
        let task = tasks[row]

        if id == "selected" {
            let button = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleSelection(_:)))
            button.state = selectedIDs.contains(task.id) ? .on : .off
            button.tag = row
            button.isEnabled = !isConverting && task.status != .succeeded
            return button
        }

        let text = NSTextField(labelWithString: value(for: id, task: task))
        text.lineBreakMode = .byTruncatingMiddle
        if id == "status" {
            text.textColor = color(for: task.status)
        }
        return text
    }

    @objc private func toggleSelection(_ sender: NSButton) {
        let task = tasks[sender.tag]
        if sender.state == .on {
            selectedIDs.insert(task.id)
        } else {
            selectedIDs.remove(task.id)
        }
        refresh()
    }

    private func value(for column: String, task: ConversionTask) -> String {
        switch column {
        case "file": return task.sourceURL.path
        case "status": return statusText(task)
        case "progress": return "\(Int(task.progress * 100))%"
        case "videoSize": return FileSizeText.format(fileSizeReader.sizeOfFile(at: task.sourceURL))
        case "mp3Size": return FileSizeText.format(fileSizeReader.sizeOfFile(at: task.outputURL))
        case "output": return task.outputURL.path
        default: return ""
        }
    }

    private func statusText(_ task: ConversionTask) -> String {
        switch task.status {
        case .pending: return "待处理"
        case .converting: return "转换中 \(Int(task.progress * 100))%"
        case .succeeded: return "成功"
        case .failed: return "失败，详情见日志"
        case .cancelled: return "已停止"
        }
    }

    private func color(for status: ConversionStatus) -> NSColor {
        switch status {
        case .succeeded: return .systemGreen
        case .failed: return .systemRed
        case .cancelled: return .systemOrange
        case .converting: return .systemBlue
        case .pending: return .labelColor
        }
    }
}

enum AppPaths {
    static func supportDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("ConvertVideo2MP3", isDirectory: true)
    }

    static func defaultLogURL() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        return supportDirectory()
            .appendingPathComponent("logs", isDirectory: true)
            .appendingPathComponent("app-\(formatter.string(from: Date())).log")
    }

    static func stateURL(for root: URL) -> URL {
        let hash = String(root.path.hashValue).replacingOccurrences(of: "-", with: "n")
        return supportDirectory()
            .appendingPathComponent("state", isDirectory: true)
            .appendingPathComponent("\(hash).json")
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.setActivationPolicy(.regular)
app.delegate = delegate
BootstrapLog.write("starting NSApplication.run")
app.run()
