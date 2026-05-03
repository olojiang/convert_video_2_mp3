import AppKit
import AVFoundation
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

    func applicationWillTerminate(_ notification: Notification) {
        windowController?.persistSession()
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

enum ArrowKeyDirection {
    case left
    case right
}

final class KeyHandlingTableView: NSTableView {
    var onSpace: ((Bool) -> Void)?
    var onReturnKey: (() -> Bool)?
    var onArrowKey: ((ArrowKeyDirection, Bool) -> Bool)?
    var onCommandBackspace: (() -> Void)?
    var onShiftCommandBackspace: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let modifierFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == 51 {
            if modifierFlags.contains(.command), modifierFlags.contains(.shift) {
                onShiftCommandBackspace?()
                return
            }

            if modifierFlags.contains(.command) {
                onCommandBackspace?()
                return
            }
        }

        if event.keyCode == 49 {
            onSpace?(event.modifierFlags.contains(.control))
            return
        }

        if event.keyCode == 36 || event.keyCode == 76 {
            if onReturnKey?() == true {
                return
            }
        }

        if event.keyCode == 123 {
            if onArrowKey?(.left, modifierFlags.contains(.shift)) == true {
                return
            }
        }

        if event.keyCode == 124 {
            if onArrowKey?(.right, modifierFlags.contains(.shift)) == true {
                return
            }
        }

        super.keyDown(with: event)
    }
}

final class SeekableProgressIndicator: NSProgressIndicator {
    var isSeekEnabled = false
    var onSeekRatio: ((Double) -> Void)?

    override func resetCursorRects() {
        super.resetCursorRects()
        if isSeekEnabled {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard isSeekEnabled else {
            super.mouseDown(with: event)
            return
        }
        seek(to: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isSeekEnabled else {
            super.mouseDragged(with: event)
            return
        }
        seek(to: event)
    }

    private func seek(to event: NSEvent) {
        guard bounds.width > 0 else { return }
        let point = convert(event.locationInWindow, from: nil)
        let ratio = min(max(point.x / bounds.width, 0), 1)
        onSeekRatio?(Double(ratio))
    }
}

private enum AppMode: String, Codable {
    case conversion
    case mp3Playback
}

final class MainWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, AVAudioPlayerDelegate {
    private let scanner = VideoScanner()
    private let mp3Scanner = MP3Scanner()
    private let partFolderCleaner = PartFolderCleaner()
    private let fileSizeReader = FileSizeReader()
    private let taskSorter = ConversionTaskSorter()
    private let mp3TrackSorter = MP3TrackSorter()
    private let historyStore = RootHistoryStore()
    private let sortPreferenceStore = TableSortPreferenceStore()
    private let mp3SortPreferenceStore = MP3SortPreferenceStore()
    private let viewPreferenceStore = ViewPreferenceStore()
    private let logger: FileEventLogger
    private var stateStore: TaskStateStore?
    private var coordinator: ConversionCoordinator?
    private var rootURL: URL?
    private var tasks: [ConversionTask] = []
    private var mp3Tracks: [MP3Track] = []
    private var selectedIDs = Set<String>()
    private var isConverting = false
    private var appMode: AppMode = .conversion
    private var sortPreference = ConversionTaskSortOption()
    private var mp3SortPreference = MP3TrackSortOption()
    private var playbackStateStore: MP3PlaybackStateStore?
    private var restoredPlaybackPosition: MP3PlaybackPosition?
    private var audioPlayer: AVAudioPlayer?
    private var currentTrackID: String?
    private var playbackTimer: Timer?

    private let rootLabel = NSTextField(labelWithString: "未选择目录")
    private let summaryLabel = NSTextField(labelWithString: "请选择一个根目录开始扫描")
    private let logLabel = NSTextField(labelWithString: "")
    private let tableView = KeyHandlingTableView()
    private let scrollView = NSScrollView()
    private let chooseButton = NSButton(title: "选择目录", target: nil, action: nil)
    private let rescanButton = NSButton(title: "重新扫描", target: nil, action: nil)
    private let modeControl = NSSegmentedControl(labels: ["转换模式", "MP3 播放"], trackingMode: .selectOne, target: nil, action: nil)
    private let selectAllButton = NSButton(title: "全选", target: nil, action: nil)
    private let selectNoneButton = NSButton(title: "清空选择", target: nil, action: nil)
    private let startButton = NSButton(title: "开始转 MP3", target: nil, action: nil)
    private let stopButton = NSButton(title: "停止", target: nil, action: nil)
    private let revealLogsButton = NSButton(title: "打开日志", target: nil, action: nil)
    private let cleanPartFoldersButton = NSButton(title: "清理 .mp4.part 文件夹", target: nil, action: nil)
    private let shortcutHelpButton = NSButton()
    private let deleteSourceCheckbox = NSButton(checkboxWithTitle: "成功后删除源视频", target: nil, action: nil)
    private let concurrencyPopup = NSPopUpButton()
    private let previousTrackButton = NSButton(title: "上一首", target: nil, action: nil)
    private let rewind30Button = NSButton(title: "-30s", target: nil, action: nil)
    private let rewind5Button = NSButton(title: "-5s", target: nil, action: nil)
    private let playPauseButton = NSButton(title: "播放", target: nil, action: nil)
    private let forward5Button = NSButton(title: "+5s", target: nil, action: nil)
    private let forward30Button = NSButton(title: "+30s", target: nil, action: nil)
    private let nextTrackButton = NSButton(title: "下一首", target: nil, action: nil)
    private let progressIndicator = SeekableProgressIndicator()

    init() {
        logger = Self.makeLogger()
        appMode = viewPreferenceStore.load()
        sortPreference = sortPreferenceStore.load()
        mp3SortPreference = mp3SortPreferenceStore.load()
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
            modeControl,
            selectAllButton,
            selectNoneButton,
            concurrencyPopup,
            deleteSourceCheckbox,
            startButton,
            stopButton,
            cleanPartFoldersButton,
            previousTrackButton,
            rewind30Button,
            rewind5Button,
            playPauseButton,
            forward5Button,
            forward30Button,
            nextTrackButton,
            revealLogsButton,
            shortcutHelpButton
        ])
        toolbar.orientation = .horizontal
        toolbar.spacing = 8
        toolbar.alignment = .centerY
        toolbar.distribution = .gravityAreas

        concurrencyPopup.addItems(withTitles: ["并发 4", "并发 6", "并发 8"])
        concurrencyPopup.selectItem(withTitle: "并发 4")
        modeControl.selectedSegment = appMode == .mp3Playback ? 1 : 0
        stopButton.isEnabled = false

        rootLabel.lineBreakMode = .byTruncatingMiddle
        summaryLabel.textColor = .secondaryLabelColor
        logLabel.textColor = .secondaryLabelColor
        logLabel.lineBreakMode = .byTruncatingMiddle
        progressIndicator.isIndeterminate = false
        progressIndicator.minValue = 0
        progressIndicator.maxValue = 1
        progressIndicator.onSeekRatio = { [weak self] ratio in
            self?.seekMP3(toProgress: ratio)
        }

        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(tableViewDoubleClicked(_:))
        tableView.autosaveName = "conversionTasksTable"
        tableView.autosaveTableColumns = true
        tableView.onSpace = { [weak self] controlPressed in
            guard let self else { return }
            if self.appMode == .mp3Playback {
                self.playFocusedMP3OrToggle()
            } else {
                self.playFocusedRow(openMP3: controlPressed)
            }
        }
        tableView.onReturnKey = { [weak self] in
            guard let self, self.appMode == .mp3Playback else { return false }
            self.playFocusedMP3OrToggle()
            return true
        }
        tableView.onArrowKey = { [weak self] direction, shiftPressed in
            guard let self, self.appMode == .mp3Playback else { return false }
            let seconds: TimeInterval = shiftPressed ? 30 : 5
            switch direction {
            case .left:
                self.seekMP3(by: -seconds)
            case .right:
                self.seekMP3(by: seconds)
            }
            return true
        }
        tableView.onCommandBackspace = { [weak self] in
            guard self?.appMode == .conversion else { return }
            self?.deleteFocusedTaskFolder()
        }
        tableView.onShiftCommandBackspace = { [weak self] in
            guard self?.appMode == .conversion else { return }
            self?.deleteFocusedSourceVideo()
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
        configureSortableColumns()
        applySortPreferenceToTableHeader()
        configureColumnsForMode()

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
        modeControl.target = self
        modeControl.action = #selector(modeChanged)
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
        previousTrackButton.target = self
        previousTrackButton.action = #selector(playPreviousTrack)
        rewind30Button.target = self
        rewind30Button.action = #selector(rewind30Seconds)
        rewind5Button.target = self
        rewind5Button.action = #selector(rewind5Seconds)
        playPauseButton.target = self
        playPauseButton.action = #selector(toggleMP3Playback)
        forward5Button.target = self
        forward5Button.action = #selector(forward5Seconds)
        forward30Button.target = self
        forward30Button.action = #selector(forward30Seconds)
        nextTrackButton.target = self
        nextTrackButton.action = #selector(playNextTrack)
        deleteSourceCheckbox.target = self
        deleteSourceCheckbox.action = #selector(deleteSourceOptionChanged)
        configureShortcutHelpButton()
        configureControlsForMode()

        logLabel.stringValue = "日志文件：\(logger.logURL.path)"
    }

    private func addColumn(id: String, title: String, width: CGFloat) {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
        column.title = title
        column.width = width
        tableView.addTableColumn(column)
    }

    private func configureSortableColumns() {
        tableColumn(id: "file")?.sortDescriptorPrototype = NSSortDescriptor(key: "fileName", ascending: true)
        tableColumn(id: "videoSize")?.sortDescriptorPrototype = NSSortDescriptor(key: "videoSize", ascending: true)
        tableColumn(id: "mp3Size")?.sortDescriptorPrototype = NSSortDescriptor(key: "mp3Size", ascending: true)
    }

    private func configureMP3SortableColumns() {
        tableColumn(id: "file")?.sortDescriptorPrototype = NSSortDescriptor(key: "mp3FileName", ascending: true)
        tableColumn(id: "videoSize")?.sortDescriptorPrototype = NSSortDescriptor(key: "mp3FileSize", ascending: true)
    }

    private func applySortPreferenceToTableHeader() {
        let key: String
        switch sortPreference.column {
        case .fileName: key = "fileName"
        case .videoSize: key = "videoSize"
        case .mp3Size: key = "mp3Size"
        }
        tableView.sortDescriptors = [
            NSSortDescriptor(key: key, ascending: sortPreference.direction == .ascending)
        ]
    }

    private func applyMP3SortPreferenceToTableHeader() {
        let key: String
        switch mp3SortPreference.column {
        case .fileName: key = "mp3FileName"
        case .fileSize: key = "mp3FileSize"
        }
        tableView.sortDescriptors = [
            NSSortDescriptor(key: key, ascending: mp3SortPreference.direction == .ascending)
        ]
    }

    private func tableColumn(id: String) -> NSTableColumn? {
        tableView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(id))
    }

    private func configureColumnsForMode() {
        switch appMode {
        case .conversion:
            configureSortableColumns()
            applySortPreferenceToTableHeader()
            tableColumn(id: "selected")?.isHidden = false
            tableColumn(id: "file")?.title = "视频文件"
            tableColumn(id: "file")?.width = 330
            tableColumn(id: "status")?.title = "状态"
            tableColumn(id: "progress")?.isHidden = false
            tableColumn(id: "progress")?.title = "进度"
            tableColumn(id: "videoSize")?.title = "视频大小"
            tableColumn(id: "mp3Size")?.isHidden = false
            tableColumn(id: "mp3Size")?.title = "MP3大小"
            tableColumn(id: "output")?.title = "输出 MP3"
            tableColumn(id: "output")?.width = 310
        case .mp3Playback:
            for column in tableView.tableColumns {
                column.sortDescriptorPrototype = nil
            }
            configureMP3SortableColumns()
            applyMP3SortPreferenceToTableHeader()
            tableColumn(id: "selected")?.isHidden = true
            tableColumn(id: "file")?.title = "MP3 文件"
            tableColumn(id: "file")?.width = 420
            tableColumn(id: "status")?.title = "播放"
            tableColumn(id: "progress")?.isHidden = true
            tableColumn(id: "progress")?.title = "位置"
            tableColumn(id: "videoSize")?.title = "大小"
            tableColumn(id: "mp3Size")?.isHidden = true
            tableColumn(id: "output")?.title = "路径"
            tableColumn(id: "output")?.width = 430
        }
    }

    private func configureControlsForMode() {
        let conversionMode = appMode == .conversion
        selectAllButton.isHidden = !conversionMode
        selectNoneButton.isHidden = !conversionMode
        concurrencyPopup.isHidden = !conversionMode
        deleteSourceCheckbox.isHidden = !conversionMode
        startButton.isHidden = !conversionMode
        stopButton.isHidden = !conversionMode
        cleanPartFoldersButton.isHidden = !conversionMode

        previousTrackButton.isHidden = conversionMode
        rewind30Button.isHidden = conversionMode
        rewind5Button.isHidden = conversionMode
        playPauseButton.isHidden = conversionMode
        forward5Button.isHidden = conversionMode
        forward30Button.isHidden = conversionMode
        nextTrackButton.isHidden = conversionMode

        if conversionMode {
            setControlsForConversion(active: isConverting)
        } else {
            chooseButton.isEnabled = true
            rescanButton.isEnabled = rootURL != nil
            modeControl.isEnabled = true
            let hasTracks = !mp3Tracks.isEmpty
            previousTrackButton.isEnabled = hasTracks
            rewind30Button.isEnabled = hasTracks
            rewind5Button.isEnabled = hasTracks
            playPauseButton.isEnabled = hasTracks
            forward5Button.isEnabled = hasTracks
            forward30Button.isEnabled = hasTracks
            nextTrackButton.isEnabled = hasTracks
        }
        updateProgressSeekability()
    }

    private func configureShortcutHelpButton() {
        shortcutHelpButton.title = ""
        shortcutHelpButton.bezelStyle = .texturedRounded
        shortcutHelpButton.imagePosition = .imageOnly
        shortcutHelpButton.isBordered = true
        shortcutHelpButton.toolTip = """
        Space：播放选中行的视频
        Ctrl+Space：播放选中行的 MP3
        MP3 播放模式双击：播放/暂停被双击的 MP3
        MP3 播放模式 Space：播放/暂停或播放选中 MP3
        MP3 播放模式 Enter：播放/暂停或播放选中 MP3
        MP3 播放模式 ←/→：后退/前进 5s
        MP3 播放模式 Shift+←/→：后退/前进 30s
        Shift+Cmd+Backspace：确认后仅删除选中源视频
        Cmd+Backspace：确认后删除选中视频所在文件夹
        """

        if let image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "快捷键") {
            shortcutHelpButton.image = image
        } else {
            shortcutHelpButton.title = "⌘"
        }
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

    @objc private func modeChanged() {
        saveCurrentPlaybackPosition()
        appMode = modeControl.selectedSegment == 1 ? .mp3Playback : .conversion
        viewPreferenceStore.save(appMode)
        if appMode == .conversion {
            stopMP3Playback()
        } else {
            coordinator?.requestStop()
        }
        configureColumnsForMode()
        configureControlsForMode()
        refresh()
    }

    private func loadRoot(_ url: URL) {
        do {
            saveCurrentPlaybackPosition()
            stopMP3Playback()
            logger.log(.info, event: "scan.started", details: ["root": url.path])
            rootURL = url
            historyStore.remember(url)
            rootLabel.stringValue = "根目录：\(url.path)"

            let appStateURL = AppPaths.stateURL(for: url)
            stateStore = TaskStateStore(stateURL: appStateURL)
            playbackStateStore = MP3PlaybackStateStore(stateURL: AppPaths.mp3PlaybackStateURL(for: url))
            let videos = try scanner.scan(root: url)
            tasks = try stateStore?.load(for: videos) ?? []
            mp3Tracks = try mp3Scanner.scan(root: url)
            restoredPlaybackPosition = try playbackStateStore?.load(for: mp3Tracks)
            applySort()
            applyMP3Sort()
            selectedIDs = Set(tasks.filter { $0.status != .succeeded }.map(\.id))
            try stateStore?.save(tasks)

            logger.log(.info, event: "scan.finished", details: [
                "root": url.path,
                "videos": "\(tasks.count)",
                "mp3_tracks": "\(mp3Tracks.count)",
                "selected": "\(selectedIDs.count)"
            ])
            configureControlsForMode()
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

    private func deleteFocusedTaskFolder() {
        guard !isConverting else {
            showMessage(title: "转换进行中", text: "请先停止或等待转换完成，再删除文件夹。")
            return
        }

        let row = tableView.selectedRow
        guard row >= 0, row < tasks.count else { return }
        guard let rootURL else { return }

        let task = tasks[row]
        let folderURL = task.sourceURL.deletingLastPathComponent()
        if folderURL.standardizedFileURL.path == rootURL.standardizedFileURL.path {
            showMessage(title: "不能删除当前根目录", text: "选中的视频就在扫描根目录下。为避免误删整个根目录，请在 Finder 中手动处理。")
            return
        }

        guard FileManager.default.fileExists(atPath: folderURL.path) else {
            showMessage(title: "文件夹不存在", text: "这个视频所在的文件夹已经不存在。")
            return
        }

        let affectedTasks = tasks.filter { isFile($0.sourceURL, inside: folderURL) }
        guard confirmDeletingTaskFolder(folderURL, affectedTaskCount: affectedTasks.count) else {
            logger.log(.info, event: "delete.task_folder.cancelled", details: [
                "folder": folderURL.path
            ])
            return
        }

        do {
            try FileManager.default.removeItem(at: folderURL)
            tasks.removeAll { isFile($0.sourceURL, inside: folderURL) }
            selectedIDs.subtract(affectedTasks.map { $0.id })
            applySort()
            try stateStore?.save(tasks)
            logger.log(.info, event: "delete.task_folder.deleted", details: [
                "folder": folderURL.path,
                "tasks_removed": "\(affectedTasks.count)"
            ])
            refresh()
        } catch {
            logger.log(.error, event: "delete.task_folder.failed", details: [
                "folder": folderURL.path,
                "error": error.localizedDescription
            ])
            showError(error)
        }
    }

    private func deleteFocusedSourceVideo() {
        guard !isConverting else {
            showMessage(title: "转换进行中", text: "请先停止或等待转换完成，再删除视频。")
            return
        }

        let row = tableView.selectedRow
        guard row >= 0, row < tasks.count else { return }

        let task = tasks[row]
        guard FileManager.default.fileExists(atPath: task.sourceURL.path) else {
            showMessage(title: "源视频不存在", text: "这个源视频已经不存在。")
            return
        }

        guard confirmDeletingSourceVideo(task.sourceURL) else {
            logger.log(.info, event: "delete.source_video.cancelled", details: [
                "source": task.sourceURL.path
            ])
            return
        }

        do {
            try FileManager.default.removeItem(at: task.sourceURL)
            tasks.removeAll { $0.id == task.id }
            selectedIDs.remove(task.id)
            applySort()
            try stateStore?.save(tasks)
            logger.log(.info, event: "delete.source_video.deleted", details: [
                "source": task.sourceURL.path,
                "output_kept": task.outputURL.path
            ])
            refresh()
        } catch {
            logger.log(.error, event: "delete.source_video.failed", details: [
                "source": task.sourceURL.path,
                "error": error.localizedDescription
            ])
            showError(error)
        }
    }

    private func confirmDeletingSourceVideo(_ sourceURL: URL) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "确认删除这个源视频？"
        alert.informativeText = "只会删除这个视频文件，所在文件夹、已生成的 MP3 和其他文件都会保留，不能通过应用撤销。\n\n\(sourceURL.path)"
        alert.addButton(withTitle: "删除视频")
        alert.addButton(withTitle: "取消")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func confirmDeletingTaskFolder(_ folderURL: URL, affectedTaskCount: Int) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "确认删除这个文件夹？"
        alert.informativeText = "将递归删除文件夹及其中所有文件，不能通过应用撤销。\n\n\(folderURL.path)\n\n表格中将移除 \(affectedTaskCount) 个视频任务。"
        alert.addButton(withTitle: "删除文件夹")
        alert.addButton(withTitle: "取消")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func isFile(_ fileURL: URL, inside folderURL: URL) -> Bool {
        let folderPath = folderURL.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        return filePath == folderPath || filePath.hasPrefix(folderPath + "/")
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
        applySort()
    }

    @MainActor private func apply(taskUpdate: ConversionTask) {
        guard let index = tasks.firstIndex(where: { $0.id == taskUpdate.id }) else { return }
        tasks[index] = taskUpdate
        applySort()
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
        modeControl.isEnabled = !active
        startButton.isEnabled = !active
        stopButton.isEnabled = active
        concurrencyPopup.isEnabled = !active
        deleteSourceCheckbox.isEnabled = !active
        cleanPartFoldersButton.isEnabled = !active
        updateProgressSeekability()
    }

    private func refresh() {
        tableView.reloadData()
        configureControlsForMode()
        guard appMode == .conversion else {
            refreshMP3Summary()
            return
        }

        let succeeded = tasks.filter { $0.status == .succeeded }.count
        let failed = tasks.filter { $0.status == .failed }.count
        let cancelled = tasks.filter { $0.status == .cancelled }.count
        let totalProgress = overallProgress()
        let sizeSummary = fileSizeReader.summary(for: tasks)
        summaryLabel.stringValue = "共 \(tasks.count) 个视频，已选择 \(selectedIDs.count)，成功 \(succeeded)，失败 \(failed)，取消 \(cancelled)，总进度 \(Int(totalProgress * 100))%，视频总大小 \(FileSizeText.format(sizeSummary.videoBytes))，MP3总大小 \(FileSizeText.format(sizeSummary.mp3Bytes))"
        progressIndicator.doubleValue = totalProgress
    }

    private func refreshMP3Summary() {
        let totalBytes = mp3Tracks.reduce(Int64(0)) { partial, track in
            partial + (fileSizeReader.sizeOfFile(at: track.url) ?? 0)
        }

        let currentText: String
        if let index = currentMP3Index(), index < mp3Tracks.count {
            let track = mp3Tracks[index]
            let time = audioPlayer?.currentTime ?? restoredPlaybackPosition?.time ?? 0
            let duration = audioPlayer?.duration
            currentText = "，当前 \(index + 1)/\(mp3Tracks.count)：\(track.url.lastPathComponent) \(formatPlaybackTime(time, duration: duration))"
        } else if let restoredPlaybackPosition,
                  let index = mp3Tracks.firstIndex(where: { $0.id == restoredPlaybackPosition.trackID }) {
            currentText = "，已记住 \(index + 1)/\(mp3Tracks.count)：\(formatPlaybackTime(restoredPlaybackPosition.time, duration: nil))"
        } else {
            currentText = ""
        }

        summaryLabel.stringValue = "共 \(mp3Tracks.count) 个 MP3，大小 \(FileSizeText.format(totalBytes))\(currentText)"
        progressIndicator.doubleValue = mp3PlaybackProgress()
    }

    private func mp3PlaybackProgress() -> Double {
        guard let player = audioPlayer, player.duration > 0 else { return 0 }
        return min(max(player.currentTime / player.duration, 0), 1)
    }

    private func applySort() {
        tasks = taskSorter.sorted(tasks, by: sortPreference)
    }

    private func applyMP3Sort() {
        mp3Tracks = mp3TrackSorter.sorted(mp3Tracks, by: mp3SortPreference)
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

    func persistSession() {
        viewPreferenceStore.save(appMode)
        sortPreferenceStore.save(sortPreference)
        mp3SortPreferenceStore.save(mp3SortPreference)
        saveCurrentPlaybackPosition()
    }

    private func playFocusedMP3OrToggle() {
        let row = tableView.selectedRow
        if row >= 0, row < mp3Tracks.count {
            let track = mp3Tracks[row]
            if currentTrackID == track.id {
                toggleMP3Playback()
            } else {
                playMP3(at: row, resumeSavedPosition: true)
            }
            return
        }

        toggleMP3Playback()
    }

    @objc private func tableViewDoubleClicked(_ sender: NSTableView) {
        guard sender === tableView,
              appMode == .mp3Playback else {
            return
        }

        let row = sender.clickedRow
        guard row >= 0, row < mp3Tracks.count else { return }
        sender.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        playFocusedMP3OrToggle()
    }

    @objc private func toggleMP3Playback() {
        guard appMode == .mp3Playback else { return }

        if let player = audioPlayer {
            if player.isPlaying {
                player.pause()
                stopPlaybackTimer()
                saveCurrentPlaybackPosition()
            } else {
                player.play()
                startPlaybackTimer()
            }
            refresh()
            return
        }

        if let restoredPlaybackPosition,
           let index = mp3Tracks.firstIndex(where: { $0.id == restoredPlaybackPosition.trackID }) {
            playMP3(at: index, resumeSavedPosition: true)
            return
        }

        let selectedRow = tableView.selectedRow
        if selectedRow >= 0, selectedRow < mp3Tracks.count {
            playMP3(at: selectedRow, resumeSavedPosition: true)
        } else if !mp3Tracks.isEmpty {
            playMP3(at: 0, resumeSavedPosition: true)
        }
    }

    @objc private func playPreviousTrack() {
        guard let index = currentMP3Index(), index > 0 else { return }
        saveCurrentPlaybackPosition()
        playMP3(at: index - 1, resumeSavedPosition: false)
    }

    @objc private func playNextTrack() {
        advanceToNextTrack(automatic: false)
    }

    private func advanceToNextTrack(automatic: Bool) {
        guard let index = currentMP3Index() else { return }
        let nextIndex = index + 1
        guard nextIndex < mp3Tracks.count else {
            if automatic {
                saveCurrentPlaybackPosition(time: 0)
                stopMP3Playback(clearCurrentTrack: false)
            }
            return
        }
        saveCurrentPlaybackPosition()
        playMP3(at: nextIndex, resumeSavedPosition: false)
    }

    @objc private func rewind30Seconds() {
        seekMP3(by: -30)
    }

    @objc private func rewind5Seconds() {
        seekMP3(by: -5)
    }

    @objc private func forward5Seconds() {
        seekMP3(by: 5)
    }

    @objc private func forward30Seconds() {
        seekMP3(by: 30)
    }

    private func playMP3(at index: Int, resumeSavedPosition: Bool) {
        guard index >= 0, index < mp3Tracks.count else { return }
        let track = mp3Tracks[index]

        do {
            stopPlaybackTimer()
            audioPlayer?.stop()
            let player = try AVAudioPlayer(contentsOf: track.url)
            player.delegate = self
            if resumeSavedPosition,
               restoredPlaybackPosition?.trackID == track.id,
               let time = restoredPlaybackPosition?.time {
                player.currentTime = min(max(0, time), max(0, player.duration - 1))
            }
            player.prepareToPlay()
            player.play()

            audioPlayer = player
            currentTrackID = track.id
            restoredPlaybackPosition = MP3PlaybackPosition(trackID: track.id, time: player.currentTime)
            tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            tableView.scrollRowToVisible(index)
            startPlaybackTimer()
            saveCurrentPlaybackPosition()
            logger.log(.info, event: "mp3.playback_started", details: [
                "track": track.url.path,
                "time": "\(Int(player.currentTime))"
            ])
            refresh()
        } catch {
            logger.log(.error, event: "mp3.playback_failed", details: [
                "track": track.url.path,
                "error": error.localizedDescription
            ])
            showError(error)
        }
    }

    private func seekMP3(by seconds: TimeInterval) {
        guard let player = audioPlayer else {
            toggleMP3Playback()
            return
        }
        player.currentTime = min(max(0, player.currentTime + seconds), player.duration)
        saveCurrentPlaybackPosition()
        refresh()
    }

    private func seekMP3(toProgress progress: Double) {
        guard appMode == .mp3Playback,
              let player = audioPlayer,
              player.duration.isFinite,
              player.duration > 0 else {
            return
        }
        player.currentTime = min(max(0, progress), 1) * player.duration
        saveCurrentPlaybackPosition()
        refresh()
    }

    private func updateProgressSeekability() {
        let canSeek = appMode == .mp3Playback
            && audioPlayer?.duration.isFinite == true
            && (audioPlayer?.duration ?? 0) > 0
        guard progressIndicator.isSeekEnabled != canSeek else { return }
        progressIndicator.isSeekEnabled = canSeek
        progressIndicator.window?.invalidateCursorRects(for: progressIndicator)
    }

    private func currentMP3Index() -> Int? {
        if let currentTrackID,
           let index = mp3Tracks.firstIndex(where: { $0.id == currentTrackID }) {
            return index
        }

        let selectedRow = tableView.selectedRow
        if selectedRow >= 0, selectedRow < mp3Tracks.count {
            return selectedRow
        }

        if let restoredPlaybackPosition {
            return mp3Tracks.firstIndex(where: { $0.id == restoredPlaybackPosition.trackID })
        }

        return nil
    }

    private func saveCurrentPlaybackPosition(time explicitTime: TimeInterval? = nil) {
        let trackID = currentTrackID ?? restoredPlaybackPosition?.trackID
        guard let trackID else { return }

        let time = explicitTime ?? audioPlayer?.currentTime ?? restoredPlaybackPosition?.time ?? 0
        let position = MP3PlaybackPosition(trackID: trackID, time: time)
        restoredPlaybackPosition = position
        try? playbackStateStore?.save(position)
    }

    private func stopMP3Playback(clearCurrentTrack: Bool = true) {
        stopPlaybackTimer()
        audioPlayer?.stop()
        audioPlayer = nil
        if clearCurrentTrack {
            currentTrackID = nil
        }
        playPauseButton.title = "播放"
        updateProgressSeekability()
    }

    private func startPlaybackTimer() {
        stopPlaybackTimer()
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.saveCurrentPlaybackPosition()
            self.refresh()
        }
        playPauseButton.title = "暂停"
        updateProgressSeekability()
    }

    private func stopPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = nil
        playPauseButton.title = audioPlayer?.isPlaying == true ? "暂停" : "播放"
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.advanceToNextTrack(automatic: true)
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        switch appMode {
        case .conversion: return tasks.count
        case .mp3Playback: return mp3Tracks.count
        }
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let id = tableColumn?.identifier.rawValue else { return nil }
        if appMode == .mp3Playback {
            guard row < mp3Tracks.count else { return nil }
            return makeTextCell(
                value(for: id, track: mp3Tracks[row]),
                color: id == "status" ? mp3StatusColor(for: mp3Tracks[row]) : .labelColor
            )
        }

        guard row < tasks.count else { return nil }
        let task = tasks[row]

        if id == "selected" {
            let button = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleSelection(_:)))
            button.state = selectedIDs.contains(task.id) ? .on : .off
            button.tag = row
            button.isEnabled = !isConverting && task.status != .succeeded
            return button
        }

        return makeTextCell(
            value(for: id, task: task),
            color: id == "status" ? color(for: task.status) : .labelColor
        )
    }

    private func makeTextCell(_ text: String, color: NSColor = .labelColor) -> NSView {
        let container = NSView()
        let label = NSTextField(labelWithString: text)
        label.lineBreakMode = .byTruncatingMiddle
        label.textColor = color
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            label.topAnchor.constraint(greaterThanOrEqualTo: container.topAnchor),
            label.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor)
        ])

        return container
    }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard let descriptor = tableView.sortDescriptors.first,
              let key = descriptor.key else {
            return
        }

        let direction: SortDirection = descriptor.ascending ? .ascending : .descending
        switch appMode {
        case .conversion:
            guard let column = sortColumn(for: key) else { return }
            sortPreference = ConversionTaskSortOption(column: column, direction: direction)
            sortPreferenceStore.save(sortPreference)
            applySort()
        case .mp3Playback:
            guard let column = mp3SortColumn(for: key) else { return }
            mp3SortPreference = MP3TrackSortOption(column: column, direction: direction)
            mp3SortPreferenceStore.save(mp3SortPreference)
            applyMP3Sort()
        }
        refresh()
    }

    private func sortColumn(for key: String) -> ConversionTaskSortColumn? {
        switch key {
        case "fileName": return .fileName
        case "videoSize": return .videoSize
        case "mp3Size": return .mp3Size
        default: return nil
        }
    }

    private func mp3SortColumn(for key: String) -> MP3TrackSortColumn? {
        switch key {
        case "mp3FileName": return .fileName
        case "mp3FileSize": return .fileSize
        default: return nil
        }
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

    private func value(for column: String, track: MP3Track) -> String {
        switch column {
        case "file": return track.url.lastPathComponent
        case "status": return mp3StatusText(for: track)
        case "progress":
            guard currentTrackID == track.id else {
                if restoredPlaybackPosition?.trackID == track.id {
                    return formatPlaybackTime(restoredPlaybackPosition?.time ?? 0, duration: nil)
                }
                return ""
            }
            return formatPlaybackTime(audioPlayer?.currentTime ?? 0, duration: audioPlayer?.duration)
        case "videoSize": return FileSizeText.format(fileSizeReader.sizeOfFile(at: track.url))
        case "output": return track.url.path
        default: return ""
        }
    }

    private func mp3StatusText(for track: MP3Track) -> String {
        guard currentTrackID == track.id else {
            return restoredPlaybackPosition?.trackID == track.id ? "已记住" : ""
        }

        if audioPlayer?.isPlaying == true {
            return "播放中"
        }
        return "已暂停"
    }

    private func mp3StatusColor(for track: MP3Track) -> NSColor {
        guard currentTrackID == track.id || restoredPlaybackPosition?.trackID == track.id else {
            return .labelColor
        }
        return audioPlayer?.isPlaying == true ? .systemBlue : .systemOrange
    }

    private func formatPlaybackTime(_ time: TimeInterval, duration: TimeInterval?) -> String {
        let current = formatClock(time)
        guard let duration, duration.isFinite, duration > 0 else { return current }
        return "\(current)/\(formatClock(duration))"
    }

    private func formatClock(_ time: TimeInterval) -> String {
        let totalSeconds = max(0, Int(time.rounded(.down)))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
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

    static func mp3PlaybackStateURL(for root: URL) -> URL {
        let hash = String(root.path.hashValue).replacingOccurrences(of: "-", with: "n")
        return supportDirectory()
            .appendingPathComponent("mp3-playback", isDirectory: true)
            .appendingPathComponent("\(hash).json")
    }
}

private struct TableSortPreferenceStore {
    private let key: String
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(key: String = "conversionTasksSortPreference", defaults: UserDefaults = .standard) {
        self.key = key
        self.defaults = defaults
    }

    func load() -> ConversionTaskSortOption {
        guard let data = defaults.data(forKey: key),
              let option = try? decoder.decode(ConversionTaskSortOption.self, from: data) else {
            return ConversionTaskSortOption()
        }
        return option
    }

    func save(_ option: ConversionTaskSortOption) {
        guard let data = try? encoder.encode(option) else { return }
        defaults.set(data, forKey: key)
    }
}

private struct MP3SortPreferenceStore {
    private let key: String
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(key: String = "mp3TracksSortPreference", defaults: UserDefaults = .standard) {
        self.key = key
        self.defaults = defaults
    }

    func load() -> MP3TrackSortOption {
        guard let data = defaults.data(forKey: key),
              let option = try? decoder.decode(MP3TrackSortOption.self, from: data) else {
            return MP3TrackSortOption()
        }
        return option
    }

    func save(_ option: MP3TrackSortOption) {
        guard let data = try? encoder.encode(option) else { return }
        defaults.set(data, forKey: key)
    }
}

private struct ViewPreferenceStore {
    private let key: String
    private let defaults: UserDefaults

    init(key: String = "mainViewMode", defaults: UserDefaults = .standard) {
        self.key = key
        self.defaults = defaults
    }

    func load() -> AppMode {
        guard let rawValue = defaults.string(forKey: key),
              let mode = AppMode(rawValue: rawValue) else {
            return .conversion
        }
        return mode
    }

    func save(_ mode: AppMode) {
        defaults.set(mode.rawValue, forKey: key)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.setActivationPolicy(.regular)
app.delegate = delegate
BootstrapLog.write("starting NSApplication.run")
app.run()
