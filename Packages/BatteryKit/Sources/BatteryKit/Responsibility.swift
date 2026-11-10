import Darwin

/// Finds the app that's responsible for a process: Safari for its web
/// content processes, Xcode for the build tools it runs, and so on.
///
/// macOS tracks this, but only exposes it through a function that isn't in
/// the public headers, so it's looked up at runtime. Should it ever go away,
/// we fall back to the parent process, which covers most helpers.
enum Responsibility {
    private typealias ResponsiblePIDFunction = @convention(c) (pid_t) -> pid_t

    private static let responsiblePIDFunction: ResponsiblePIDFunction? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid")
        else { return nil }
        return unsafeBitCast(symbol, to: ResponsiblePIDFunction.self)
    }()

    static func responsiblePID(for pid: pid_t) -> pid_t {
        if let responsiblePIDFunction {
            let responsible = responsiblePIDFunction(pid)
            if responsible > 0 { return responsible }
        }
        return parentPID(of: pid) ?? pid
    }

    private static func parentPID(of pid: pid_t) -> pid_t? {
        var info = proc_bsdshortinfo()
        let size = Int32(MemoryLayout<proc_bsdshortinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 0, &info, size) == size else { return nil }
        let parent = pid_t(info.pbsi_ppid)
        // launchd (1) adopts everything; that isn't a meaningful owner.
        return parent > 1 ? parent : pid
    }
}
