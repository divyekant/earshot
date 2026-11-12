import Foundation
import PACore
#if canImport(CoreServices)
import CoreServices

/// The watch on kept folders with FSEvents (phase 2 build spec, 8.5). One stream for all kept folders, with file
/// events and a latency of 2 s, so that a file that an app writes in parts comes as one change.
public final class FSEventsWatcher: FolderWatcher {
    private var stream: FSEventStreamRef?
    private var handler: (([String]) -> Void)?
    private let queue = DispatchQueue(label: "earshot.pa.fsevents", qos: .utility)

    public init() {}

    public func watch(_ folders: [String], _ handler: @escaping ([String]) -> Void) {
        stop()
        guard !folders.isEmpty else { return }
        self.handler = handler
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let me = Unmanaged<FSEventsWatcher>.fromOpaque(info).takeUnretainedValue()
            let list = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
            if !list.isEmpty { me.handler?(Array(list.prefix(count))) }
        }
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer)
        guard let s = FSEventStreamCreate(nil, callback, &context, folders as CFArray,
                                          FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 2.0, flags) else { return }
        FSEventStreamSetDispatchQueue(s, queue)
        FSEventStreamStart(s)
        stream = s
    }

    func stop() {
        guard let s = stream else { return }
        FSEventStreamStop(s)
        FSEventStreamInvalidate(s)
        FSEventStreamRelease(s)
        stream = nil
    }

    deinit { stop() }
}
#endif
