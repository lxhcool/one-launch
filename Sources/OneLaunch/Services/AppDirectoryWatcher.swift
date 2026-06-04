import CoreServices
import Foundation

/// 使用 FSEvents 监听应用安装目录的变化，自动触发应用列表刷新
final class AppDirectoryWatcher {
    private var stream: FSEventStreamRef?
    private var onChange: (() -> Void)?
    private var debounceTask: DispatchWorkItem?

    init() {}

    func start(onChange: @escaping () -> Void) {
        guard stream == nil else { return }
        self.onChange = onChange

        let paths = applicationRoots()

        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { _, info, _, _, _, _ in
                guard let info else { return }
                let watcher = Unmanaged<AppDirectoryWatcher>.fromOpaque(info).takeUnretainedValue()
                watcher.handleChange()
            },
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0, // 延迟 1 秒聚合
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagWatchRoot)
        ) else { return }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    private func handleChange() {
        debounceTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            self?.onChange?()
        }
        debounceTask = task
        // 额外防抖：文件系统事件可能频繁触发，等 0.5 秒静默后再执行
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: task)
    }

    private func applicationRoots() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            "/Applications",
            "/System/Applications",
            home.appendingPathComponent("Applications", isDirectory: true).path
        ]
    }

    deinit {
        stop()
    }
}
