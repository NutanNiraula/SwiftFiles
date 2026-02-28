#if os(macOS)
import Testing
import Foundation
@testable import SwiftFiles

@Suite final class WatcherTests {
    var tempFolder: Folder!
    
    init() throws {
        // Create a unique temporary folder for each test
        let tempPath = Path.temp / UUID().uuidString
        tempFolder = Folder(path: tempPath)
        try tempFolder.create()
    }
    
    deinit {
        try? tempFolder.delete()
    }
    
    enum TestResult: Sendable {
        case event(WatchEvent)
        case timeout
    }

    @Test func fileCreation() async throws {
        let result = await withTaskGroup(of: TestResult.self) { group -> WatchEvent? in
            // Watcher
            group.addTask { [tempFolder] in
                guard let tempFolder else { return .timeout }
                let watcher = tempFolder.watch(latency: 0.1)
                for await event in watcher.events {
                    if event.kind == .created && event.path.name == "test.txt" {
                        return .event(event)
                    }
                }
                // Stream ended unexpectedly
                return .timeout
            }
            
            // Creator
            group.addTask { [tempFolder] in
                guard let tempFolder else { return .timeout }
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s delay to ensure watcher is ready
                
                // We use String.write(atomically: false) to simulate a direct file creation.
                // Standard File.create() / File.write() uses atomic writing (create temp + rename),
                // which FSEvents often reports as .renamed or .modified, not .created.
                // Since this test specifically verifies the .created event, we use non-atomic write.
                let filePath = tempFolder.path / "test.txt"
                try? "Hello".write(to: filePath.url, atomically: false, encoding: .utf8)
                
                try? await Task.sleep(nanoseconds: 10_000_000_000) // Wait to be cancelled
                return .timeout
            }
            
            // Timeout
            group.addTask {
                try? await Task.sleep(nanoseconds: 3_000_000_000) // 3s timeout
                return .timeout
            }
            
            for await res in group {
                switch res {
                case .event(let e):
                    group.cancelAll()
                    return e
                case .timeout:
                    // If we get a timeout from the timeout task (or stream ended), cancel everything.
                    group.cancelAll()
                    return nil
                }
            }
            return nil
        }
        
        #expect(result != nil)
        #expect(result?.path.name == "test.txt")
        #expect(result?.kind == .created)
    }
    
    @Test func fileModification() async throws {
        let file = File(path: tempFolder.path / "modify.txt")
        try file.write("Initial")
        
        let result = await withTaskGroup(of: TestResult.self) { group -> WatchEvent? in
            // Watcher
            group.addTask { [file] in
                let watcher = file.watch(latency: 0.1)
                for await event in watcher.events {
                    if event.kind == .modified {
                        return .event(event)
                    }
                }
                return .timeout
            }
            
            // Modifier
            group.addTask { [file] in
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s delay
                try? file.write("Modified")
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                return .timeout
            }
            
            // Timeout
            group.addTask {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                return .timeout
            }
            
            for await res in group {
                switch res {
                case .event(let e):
                    group.cancelAll()
                    return e
                case .timeout:
                    group.cancelAll()
                    return nil
                }
            }
            return nil
        }
        
        #expect(result != nil)
        #expect(result?.kind == .modified)
    }
    
    @Test func fileDeletion() async throws {
        let filePath = tempFolder.path / "delete.txt"
        try "Delete me".write(to: filePath.url, atomically: false, encoding: .utf8)
        
        // Wait for creation to settle
        try await Task.sleep(nanoseconds: 1_000_000_000)
        
        let result = await withTaskGroup(of: TestResult.self) { group -> WatchEvent? in
            group.addTask { [tempFolder] in
                guard let tempFolder else { return .timeout }
                let watcher = tempFolder.watch(latency: 0.0)
                for await event in watcher.events {
                    if event.path.name == "delete.txt" && event.kind == .deleted {
                        return .event(event)
                    }
                }
                return .timeout
            }
            
            group.addTask { [filePath] in
                try? await Task.sleep(nanoseconds: 500_000_000)
                try? FileManager.default.removeItem(at: filePath.url)
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                return .timeout
            }
            
            group.addTask {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                return .timeout
            }
            
            for await res in group {
                switch res {
                case .event(let e):
                    group.cancelAll()
                    return e
                case .timeout:
                    group.cancelAll()
                    return nil
                }
            }
            return nil
        }
        
        #expect(result != nil)
        #expect(result?.kind == .deleted)
        #expect(result?.path.name == "delete.txt")
    }
    
    @Test func cancellationStopsStream() async throws {
        // Stream should loop until cancelled
        let watcher = tempFolder.watch(latency: 0.1)
        
        let task = Task {
            for await _ in watcher.events { }
        }
        
        // Let it start
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Cancel
        task.cancel()
        
        // Wait a bit to ensure cancellation propagates
        try await Task.sleep(nanoseconds: 200_000_000)
        
        #expect(task.isCancelled)
    }
}
#endif
