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
        if flags & UInt32(kFSEventStreamEventFlagItemRemoved) != 0 { return .deleted }
        if flags & UInt32(kFSEventStreamEventFlagItemCreated) != 0 { return .created }
        if flags & UInt32(kFSEventStreamEventFlagItemModified) != 0 { return .modified }
        if flags & UInt32(kFSEventStreamEventFlagItemInodeMetaMod) != 0 { return .modified }
        if flags & UInt32(kFSEventStreamEventFlagItemRenamed) != 0 { return .modified }
        return nil
    }
}

public final class Watcher: Sendable {
    private let paths: [Path]
    private let latency: TimeInterval
    
    public init(paths: [Path], latency: TimeInterval = 0.1) {
        self.paths = paths
        self.latency = latency
    }
    
    public convenience init(_ nodes: any FSNode..., latency: TimeInterval = 0.1) {
        self.init(paths: nodes.map(\.path), latency: latency)
    }
    
    public var events: AsyncStream<WatchEvent> {
        AsyncStream { continuation in
            let state = StreamState(continuation: continuation)
            
            continuation.onTermination = { _ in
                state.stop()
            }
            
            let cfPaths = paths.map { ($0.url.resolvingSymlinksInPath().path as NSString) as CFString } as CFArray
            let retainedState = Unmanaged.passRetained(state)
            
            var context = FSEventStreamContext(
                version: 0,
                info: retainedState.toOpaque(),
                retain: nil,
                release: { ptr in
                    guard let ptr else { return }
                    Unmanaged<StreamState>.fromOpaque(ptr).release()
                },
                copyDescription: nil
            )
            
            let flags = FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagFileEvents |
                kFSEventStreamCreateFlagUseCFTypes |
                kFSEventStreamCreateFlagNoDefer
            )
            
            guard let stream = FSEventStreamCreate(
                kCFAllocatorDefault,
                { _, info, numEvents, eventPaths, eventFlags, _ in
                    guard let info else { return }
                    let state = Unmanaged<StreamState>.fromOpaque(info).takeUnretainedValue()
                    let eventPathArray = unsafeBitCast(eventPaths, to: NSArray.self)
                    
                    for i in 0..<numEvents {
                        let flags = eventFlags[i]
                        guard
                            let rawPath = eventPathArray[i] as? String,
                            let kind = WatchEvent.Kind.from(flags: flags)
                        else { continue }
                        
                        state.continuation.yield(WatchEvent(path: Path(rawPath), kind: kind))
                    }
                },
                &context,
                cfPaths,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                latency,
                flags
            ) else {
                retainedState.release()
                continuation.finish()
                return
            }
            
            guard state.install(stream: stream) else {
                FSEventStreamInvalidate(stream)
                FSEventStreamRelease(stream)
                continuation.finish()
                return
            }
            
            let queue = DispatchQueue(
                label: "com.swiftfiles.watcher.\(UUID().uuidString)",
                qos: .utility
            )
            
            FSEventStreamSetDispatchQueue(stream, queue)
            
            guard FSEventStreamStart(stream) else {
                state.stop()
                continuation.finish()
                return
            }
        }
    }
}

private final class StreamState: @unchecked Sendable {
    let continuation: AsyncStream<WatchEvent>.Continuation
    
    private let lock = NSLock()
    private var stream: FSEventStreamRef?
    private var stopped = false
    
    init(continuation: AsyncStream<WatchEvent>.Continuation) {
        self.continuation = continuation
    }
    
    func install(stream: FSEventStreamRef) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        guard !stopped else { return false }
        self.stream = stream
        return true
    }
    
    func stop() {
        let streamToStop: FSEventStreamRef?
        
        lock.lock()
        if stopped {
            lock.unlock()
            return
        }
        stopped = true
        streamToStop = stream
        stream = nil
        lock.unlock()
        
        guard let streamToStop else { return }
        FSEventStreamStop(streamToStop)
        FSEventStreamInvalidate(streamToStop)
        FSEventStreamRelease(streamToStop)
    }
}

public extension FSNode {
    func watch(latency: TimeInterval = 0.1) -> Watcher {
        Watcher(paths: [path], latency: latency)
    }
}
#endif
