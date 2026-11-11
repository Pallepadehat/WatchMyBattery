import Foundation
import OSLog

// WatchMyBatteryHelper: a tiny launchd daemon, started on demand when the app
// asks to change Low Power Mode, and gone again shortly after. It runs as
// root, so it does exactly one thing: `pmset -a lowpowermode 0|1`, for
// WatchMyBattery only.

let logger = Logger(subsystem: HelperIdentity.label, category: "helper")

/// Quits after a while without requests; launchd starts it again on the next one.
final class IdleTimer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "idle")
    private var work: DispatchWorkItem?

    func restart() {
        queue.async { [self] in
            work?.cancel()
            let work = DispatchWorkItem { exit(0) }
            self.work = work
            queue.asyncAfter(deadline: .now() + 30, execute: work)
        }
    }
}

final class Helper: NSObject, LowPowerModeHelperProtocol {
    let idle: IdleTimer

    init(idle: IdleTimer) {
        self.idle = idle
    }

    func setLowPowerMode(_ on: Bool, reply: @escaping @Sendable (String?) -> Void) {
        idle.restart()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-a", "lowpowermode", on ? "1" : "0"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                logger.notice("Turned Low Power Mode \(on ? "on" : "off", privacy: .public)")
                reply(nil)
            } else {
                logger.error("pmset failed: \(output, privacy: .public)")
                reply(output.isEmpty ? "pmset exited with \(process.terminationStatus)" : output)
            }
        } catch {
            reply(error.localizedDescription)
        }
    }
}

final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    let idle = IdleTimer()

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        // Only WatchMyBattery, signed by the same team as this helper. An ad hoc
        // signed helper has no team to check against, so it accepts no one.
        guard let requirement = HelperIdentity.requirement(forIdentifier: HelperIdentity.appIdentifier) else {
            logger.error("Not signed by a team, so refusing all connections")
            return false
        }
        connection.setCodeSigningRequirement(requirement)
        connection.exportedInterface = NSXPCInterface(with: LowPowerModeHelperProtocol.self)
        connection.exportedObject = Helper(idle: idle)
        connection.resume()
        idle.restart()
        return true
    }
}

let delegate = ListenerDelegate()
let listener = NSXPCListener(machServiceName: HelperIdentity.label)
listener.delegate = delegate
listener.resume()
delegate.idle.restart()
dispatchMain()
