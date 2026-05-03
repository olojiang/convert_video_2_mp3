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
        cancellation: CancellationChecking
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

    public func convert(tasks: [ConversionTask], concurrency: Int) async -> [ConversionTask] {
        let limit = max(1, min(concurrency, 16))
        var results = tasks
        var nextIndex = 0
        var activeCount = 0

        logger.log(.info, event: "conversion.batch_started", details: [
            "total": "\(tasks.count)",
            "concurrency": "\(limit)"
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
                        var task = tasks[index]
                        return await Self.convertOne(
                            index: index,
                            task: &task,
                            extractor: extractor,
                            logger: logger,
                            onTaskUpdate: onTaskUpdate,
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
        task: inout ConversionTask,
        extractor: AudioExtracting,
        logger: EventLogger,
        onTaskUpdate: (ConversionTask) -> Void,
        cancellation: CancellationChecking
    ) async -> (Int, ConversionTask) {
        if cancellation.isCancellationRequested {
            task.status = .cancelled
            task.updatedAt = Date()
            onTaskUpdate(task)
            return (index, task)
        }

        let tempOutput = task.outputURL
            .deletingLastPathComponent()
            .appendingPathComponent(".\(task.outputURL.lastPathComponent).part")

        if FileManager.default.fileExists(atPath: task.outputURL.path) {
            task.status = .succeeded
            task.errorMessage = nil
            task.updatedAt = Date()
            logger.log(.info, event: "conversion.skipped_existing_output", details: [
                "source": task.sourceURL.path,
                "output": task.outputURL.path,
                "status": task.status.rawValue
            ])
            onTaskUpdate(task)
            return (index, task)
        }

        task.status = .converting
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
                cancellation: cancellation
            )
            task.status = .succeeded
            task.updatedAt = Date()
            logger.log(.info, event: "conversion.succeeded", details: [
                "source": task.sourceURL.path,
                "output": task.outputURL.path,
                "status": task.status.rawValue
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
