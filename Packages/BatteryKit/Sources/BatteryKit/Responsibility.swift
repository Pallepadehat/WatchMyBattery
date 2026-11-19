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

/// Who a process's energy is credited to: usually its responsible app, but a command you typed in a terminal, and a
/// program that runs on its own in the background, are their own owners.
///
/// macOS makes the terminal responsible for everything started in it, so `npm run dev` or `cargo build` would count
/// as Terminal (or iTerm, Ghostty, Visual Studio Code…), and quitting Terminal is rarely what you'd want. So a
/// process started from a shell belongs to the command typed at that shell, the one right below it, along with
/// everything that command starts. A program that has detached and runs by itself (`colima`, a VM, a server started
/// with `&` and `disown`, launched by a terminal but adopted by launchd) belongs to itself, since quitting the terminal
/// wouldn't stop it either.
public enum Ownership {
    /// Shells, by their process name. A process right below one of these is a command someone typed.
    static let shells: Set<String> = ["zsh", "bash", "sh", "fish", "dash", "ksh", "tcsh", "csh", "nu", "xonsh", "pwsh", "elvish"]

    /// How far up the parents are followed: further than any real nesting, and a stop should the table ever loop.
    static let maximumDepth = 32

    /// The process `pid`'s energy counts toward.
    public static func owner(of pid: pid_t) -> pid_t {
        owner(
            of: pid, responsible: Responsibility.responsiblePID(for: pid), parent: parentPID(of:), name: shortName(of:),
            path: { ProcessName.path(of: $0) })
    }

    /// The walk itself, with the process table passed in so it can be tested with a made-up one.
    ///
    /// Goes up from `pid` to its responsible process, collecting the line of parents. Read from the top down, the
    /// first shell on that line marks a command: the process just below it owns `pid`. Without a shell, a line that
    /// ends at launchd before reaching the responsible process has come loose from it, and its topmost process owns
    /// it, as long as it's a program of its own: an app's helpers and services (anything inside a `.app` or `.xpc`)
    /// are started by launchd too, and stay with their app. Otherwise, as before, the responsible process does.
    static func owner(
        of pid: pid_t, responsible: pid_t, parent: (pid_t) -> pid_t?, name: (pid_t) -> String?, path: (pid_t) -> String?
    ) -> pid_t {
        guard pid != responsible else { return pid }
        var line: [pid_t] = [pid]  // bottom up
        var reachedResponsible = false
        var current = pid
        while line.count < maximumDepth, let up = parent(current), up > 1 {
            if up == responsible {
                reachedResponsible = true
                break
            }
            line.append(up)
            current = up
        }
        // From the top down: the first shell, and the process below it.
        for index in stride(from: line.count - 1, through: 1, by: -1) where isShell(line[index], name: name) {
            return line[index - 1]
        }
        // A shell with nothing running in it is the terminal's, like its other processes.
        guard !reachedResponsible, line.count < maximumDepth, let top = line.last else { return responsible }
        guard let executable = path(top), !executable.contains(".app/"), !executable.contains(".xpc/") else { return responsible }
        return top
    }

    /// Started by something else that macOS still holds responsible for it (a terminal, say), rather than by macOS for
    /// itself: a command sent to the background with `&` or `nohup`, an `ssh -f` tunnel. macOS's own background
    /// processes are responsible for themselves.
    public static func isStartedByAnother(_ pid: pid_t) -> Bool {
        Responsibility.responsiblePID(for: pid) != pid
    }

    /// The process macOS holds responsible for this one: for a command, the terminal (or editor) it runs in.
    public static func responsiblePID(of pid: pid_t) -> pid_t {
        Responsibility.responsiblePID(for: pid)
    }

    /// Started at a shell's prompt: a command someone typed (or a script ran), whatever the program is.
    public static func isCommand(_ pid: pid_t) -> Bool {
        guard let parent = parentPID(of: pid), parent > 1 else { return false }
        return isShell(parent, name: shortName(of:))
    }

    private static func isShell(_ pid: pid_t, name: (pid_t) -> String?) -> Bool {
        guard var name = name(pid) else { return false }
        if name.hasPrefix("-") { name.removeFirst() }  // a login shell: "-zsh"
        return shells.contains(name)
    }

    static func parentPID(of pid: pid_t) -> pid_t? {
        var info = proc_bsdshortinfo()
        let size = Int32(MemoryLayout<proc_bsdshortinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 0, &info, size) == size else { return nil }
        return pid_t(info.pbsi_ppid)
    }

    /// The kernel's short name for the process (its executable's, up to 16 characters): plenty to tell a shell.
    static func shortName(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 64)
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
