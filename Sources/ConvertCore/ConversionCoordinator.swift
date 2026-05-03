import Foundation

public protocol CancellationChecking: AnyObject {
    var isCancellationRequested: Bool { get }
}

public final class CancellationToken: CancellationChecking {
    private let lock = NSLock()
    private var requested = false

    public init() {}

    public var isCancellationRequested: Bool {
        lock.lock()
        defer { lock.unlock() }
        return requested
    }

    public func requestCancel() {
        lock.lock()
        requested = true
        lock.unlock()
    }
}

public protocol AudioExtracting: AnyObject {
    func extractMP3(
        source: URL,
        tempOutput: URL,
        finalOutput: URL,
        cancellation: CancellationChecking,
        progress: @escaping (Double) -> Void
    ) async throws
}

public final class ConversionCoordinator {
    private let extractor: AudioExtracting
    private let logger: EventLogger
    private let onTaskUpdate: (ConversionTask) -> Void
    private let cancellation = CancellationToken()

    public init(
        extractor: AudioExtracting,
        logger: EventLogger,
        onTaskUpdate: @escaping (ConversionTask) -> Void = { _ in }
    ) {
        self.extractor = extractor
        self.logger = logger
        self.onTaskUpdate = onTaskUpdate
    }

    public func requestStop() {
        logger.log(.warning, event: "conversion.stop_requested", details: [:])
        cancellation.requestCancel()
    }

    public func convert(
        tasks: [ConversionTask],
        concurrency: Int,
        options: ConversionOptions = ConversionOptions()
    ) async -> [ConversionTask] {
        let limit = max(1, min(concurrency, 16))
        var results = tasks
        var nextIndex = 0
        var activeCount = 0

        logger.log(.info, event: "conversion.batch_started", details: [
            "total": "\(tasks.count)",
            "concurrency": "\(limit)",
            "delete_source_on_success": "\(options.deleteSourceOnSuccess)"
        ])

        await withTaskGroup(of: (Int, ConversionTask).self) { group in
            func enqueueAvailableWork() {
                while activeCount < limit,
                      nextIndex < tasks.count,
                      !cancellation.isCancellationRequested {
                    let index = nextIndex
                    nextIndex += 1
                    activeCount += 1
                    group.addTask { [extractor, logger, cancellation, onTaskUpdate] in
                        return await Self.convertOne(
                            index: index,
                            task: tasks[index],
                            extractor: extractor,
                            logger: logger,
                            onTaskUpdate: onTaskUpdate,
                            options: options,
                            cancellation: cancellation
                        )
                    }
                }
            }

            enqueueAvailableWork()
            while activeCount > 0 {
                guard let (index, task) = await group.next() else { break }
                results[index] = task
                activeCount -= 1
                enqueueAvailableWork()
            }
        }

        if cancellation.isCancellationRequested {
            for index in results.indices where results[index].status == .pending {
                results[index].status = .cancelled
                results[index].updatedAt = Date()
            }
        }

        logger.log(.info, event: "conversion.batch_finished", details: [
            "succeeded": "\(results.filter { $0.status == .succeeded }.count)",
            "failed": "\(results.filter { $0.status == .failed }.count)",
            "cancelled": "\(results.filter { $0.status == .cancelled }.count)"
        ])

        return results
    }

    private static func convertOne(
        index: Int,
        task originalTask: ConversionTask,
        extractor: AudioExtracting,
        logger: EventLogger,
        onTaskUpdate: @escaping (ConversionTask) -> Void,
        options: ConversionOptions,
        cancellation: CancellationChecking
    ) async -> (Int, ConversionTask) {
        var task = originalTask
        if cancellation.isCancellationRequested {
            task.status = .cancelled
            task.progress = 0
            task.updatedAt = Date()
            onTaskUpdate(task)
            return (index, task)
        }

        let tempOutput = task.outputURL
            .deletingLastPathComponent()
            .appendingPathComponent(".\(task.outputURL.lastPathComponent).part")

        if FileManager.default.fileExists(atPath: task.outputURL.path) {
            task.status = .succeeded
            task.progress = 1
            task.errorMessage = nil
            task.updatedAt = Date()
            logger.log(.info, event: "conversion.skipped_existing_output", details: [
                "source": task.sourceURL.path,
                "output": task.outputURL.path,
                "status": task.status.rawValue
            ])
            if options.deleteSourceOnSuccess,
               FileManager.default.fileExists(atPath: task.sourceURL.path) {
                do {
                    try FileManager.default.removeItem(at: task.sourceURL)
                    task.updatedAt = Date()
                    logger.log(.info, event: "conversion.source_deleted", details: [
                        "source": task.sourceURL.path,
                        "output": task.outputURL.path
                    ])
                } catch {
                    task.status = .failed
                    task.errorMessage = error.localizedDescription
                    task.updatedAt = Date()
                    logger.log(.error, event: "conversion.source_delete_failed", details: [
                        "source": task.sourceURL.path,
                        "output": task.outputURL.path,
                        "status": task.status.rawValue,
                        "error": error.localizedDescription
                    ])
                }
            }
            onTaskUpdate(task)
            return (index, task)
        }

        task.status = .converting
        task.progress = 0
        task.errorMessage = nil
        task.updatedAt = Date()
        onTaskUpdate(task)
        logger.log(.info, event: "conversion.started", details: [
            "source": task.sourceURL.path,
            "output": task.outputURL.path,
            "status": task.status.rawValue
        ])

        do {
            if FileManager.default.fileExists(atPath: tempOutput.path) {
                try FileManager.default.removeItem(at: tempOutput)
            }
            try await extractor.extractMP3(
                source: task.sourceURL,
                tempOutput: tempOutput,
                finalOutput: task.outputURL,
                cancellation: cancellation,
                progress: { fraction in
                    task.progress = min(max(fraction, 0), 1)
                    task.updatedAt = Date()
                    logger.log(.debug, event: "conversion.progress", details: [
                        "source": task.sourceURL.path,
                        "output": task.outputURL.path,
                        "progress": "\(Int(task.progress * 100))",
                        "status": task.status.rawValue
                    ])
                    onTaskUpdate(task)
                }
            )
            task.status = .succeeded
            task.progress = 1
            task.updatedAt = Date()
            if options.deleteSourceOnSuccess {
                try FileManager.default.removeItem(at: task.sourceURL)
                logger.log(.info, event: "conversion.source_deleted", details: [
                    "source": task.sourceURL.path,
                    "output": task.outputURL.path
                ])
            }
            logger.log(.info, event: "conversion.succeeded", details: [
                "source": task.sourceURL.path,
                "output": task.outputURL.path,
                "status": task.status.rawValue,
                "progress": "\(Int(task.progress * 100))"
            ])
            onTaskUpdate(task)
        } catch ConversionError.cancelled {
            task.status = .cancelled
            task.errorMessage = ConversionError.cancelled.localizedDescription
            task.updatedAt = Date()
            logger.log(.warning, event: "conversion.cancelled", details: [
                "source": task.sourceURL.path,
                "status": task.status.rawValue
            ])
            onTaskUpdate(task)
        } catch {
            task.status = .failed
            task.errorMessage = error.localizedDescription
            task.updatedAt = Date()
            logger.log(.error, event: "conversion.failed", details: [
                "source": task.sourceURL.path,
                "output": task.outputURL.path,
                "status": task.status.rawValue,
                "error": error.localizedDescription
            ])
            onTaskUpdate(task)
        }

        return (index, task)
    }
}
