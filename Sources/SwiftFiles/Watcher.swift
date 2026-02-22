
// MARK: - WatchEvent.swift

#if os(macOS)
import Foundation
import CoreServices

public struct WatchEvent: Sendable {
    public enum Kind: Sendable {
        case created
        case modified
        case deleted
    }
    public let path: Path
    public let kind: Kind
}

private extension WatchEvent.Kind {
    static func from(flags: FSEventStreamEventFlags) -> WatchEvent.Kind? {
        if flags & UInt32(kFSEventStreamEventFlagItemCreated) != 0 { return .created }
        if flags & UInt32(kFSEventStreamEventFlagItemRemoved) != 0 { return .deleted }
        if flags & UInt32(kFSEventStreamEventFlagItemModified) != 0 { return .modified }
        if flags & UInt32(kFSEventStreamEventFlagItemInodeMetaMod) != 0 { return .modified }
        return nil
    }
}

// MARK: - Watcher.swift

public final class Watcher: Sendable {
    private let paths: [Path]
    private let latency: TimeInterval

    public init(
        paths: [Path],
        latency: TimeInterval = 0.1
    ) {
        self.paths = paths
        self.latency = latency
    }
    
    public convenience init(
        _ nodes: any FSNode...,
        latency: TimeInterval = 0.1
    ) {
        self.init(paths: nodes.map(\.path), latency: latency)
    }
    
    public var events: AsyncStream<WatchEvent> {
        AsyncStream { continuation in
            let state = StreamState(continuation: continuation)
            let cfPaths = paths.map { $0.string as CFString } as CFArray
            
            var context = FSEventStreamContext(
                version: 0,
                info: Unmanaged.passRetained(state).toOpaque(),
                retain: nil,
                release: { ptr in
                    guard let ptr else { return }
                    Unmanaged<StreamState>.fromOpaque(ptr).release()
                },
                copyDescription: nil
            )
            
            let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
            
            guard let stream = FSEventStreamCreate(
                kCFAllocatorDefault,
                { _, info, numEvents, eventPaths, eventFlags, _ in
                    guard let info else { return }
                    let state = Unmanaged<StreamState>
                        .fromOpaque(info)
                        .takeUnretainedValue()

                    let paths = unsafeBitCast(eventPaths, to: NSArray.self)
                    for i in 0..<numEvents {
                        guard let rawPath = paths[i] as? String, let kind = WatchEvent.Kind.from(flags: eventFlags[i]) else { continue }
                        state.continuation.yield(
                            WatchEvent(path: Path(rawPath), kind: kind)
                        )
                    }
                },
                &context,
                cfPaths,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                latency,
                flags
            ) else {
                continuation.finish()
                return
            }
            
            // Use a DispatchQueue instead of RunLoop — works correctly
            // in CLIs, daemons, and headless environments
            let queue = DispatchQueue(
                label: "com.filewatcher.\(UUID().uuidString)",
                qos: .utility
            )
            
            state.stream = stream
            
            FSEventStreamSetDispatchQueue(stream, queue)
            FSEventStreamStart(stream)
            
            continuation.onTermination = { [state] _ in
                guard let stream = state.stream else { return }
                FSEventStreamStop(stream)
                FSEventStreamInvalidate(stream)
                FSEventStreamRelease(stream)
            }
        }
    }
}

// MARK: - StreamState

// Owns the FSEventStream reference and continuation together,
// making lifetime explicit and safe across the C callback boundary.
// @unchecked Sendable is justified: continuation.yield is thread-safe,
// and stream is written once before any callbacks fire.
private final class StreamState: @unchecked Sendable {
    let continuation: AsyncStream<WatchEvent>.Continuation
    var stream: FSEventStreamRef?
    
    init(continuation: AsyncStream<WatchEvent>.Continuation) {
        self.continuation = continuation
    }
}

// MARK: - FSNode Integration

public extension FSNode {
    func watch(
        latency: TimeInterval = 0.1
    ) -> Watcher {
        Watcher(paths: [path], latency: latency)
    }
}
#endif
