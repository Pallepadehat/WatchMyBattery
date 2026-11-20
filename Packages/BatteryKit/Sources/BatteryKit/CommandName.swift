import Darwin
import Foundation

/// A friendly name for a program that isn't an app: `claude` rather than `node`, `http.server` rather than `python3`.
///
/// Most programs are named by their executable. Scripts run by an interpreter (Node, Python, Ruby…) would all be called
/// after the interpreter, so for those the script is named instead, from the command line the program was started
/// with.
public enum CommandName {
    /// Programs that run a script named on their command line.
    static let interpreters: Set<String> = ["node", "python", "python3", "ruby", "perl", "php", "bun", "deno", "java", "Python"]
    /// Script files with these names say nothing; the folder (or package) they're in does.
    static let genericScripts: Set<String> = ["cli", "index", "main", "bin", "run", "app", "server", "start", "__main__"]

    /// The program `pid` is running, named as above; `nil` when it may not be read.
    public static func of(_ pid: pid_t) -> String? {
        guard let arguments = arguments(of: pid), !arguments.isEmpty else {
            return ProcessName.path(of: pid).flatMap { $0.split(separator: "/").last.map(String.init) }
        }
        return name(fromArguments: arguments, executable: ProcessName.path(of: pid))
    }

    /// From a command line (its first argument being the program, as typed). Separate so it can be tested.
    static func name(fromArguments arguments: [String], executable: String?) -> String {
        let program = basename(executable ?? arguments[0])
        // "python3.12" is python3.
        let interpreter = program.split(separator: ".").first.map(String.init) ?? program
        guard interpreters.contains(interpreter) || interpreters.contains(program) else { return program }
        var rest = arguments.dropFirst()
        while let argument = rest.first {
            rest = rest.dropFirst()
            // `python3 -m http.server`: the module.
            if argument == "-m", let module = rest.first { return module }
            if argument.hasPrefix("-") { continue }
            return scriptName(argument)
        }
        return program
    }

    /// `…/node_modules/@scope/tool/cli.js` → "tool"; `…/bin/npm-cli.js` → "npm-cli"; `server.py` → "server".
    static func scriptName(_ path: String) -> String {
        let parts = path.split(separator: "/").map(String.init)
        guard let last = parts.last else { return path }
        let name = last.split(separator: ".").first.map(String.init) ?? last
        guard genericScripts.contains(name) else { return name }
        // The package it's in: the folder after node_modules (and its scope), or simply the folder above.
        if let modules = parts.lastIndex(of: "node_modules"), modules + 1 < parts.count - 1 {
            let package = parts[modules + 1]
            if package.hasPrefix("@"), modules + 2 < parts.count - 1 { return parts[modules + 2] }
            return package
        }
        var folders = parts.dropLast()
        while let folder = folders.last, ["bin", "dist", "lib", "src", "build", "out"].contains(folder) { folders = folders.dropLast() }
        return folders.last ?? name
    }

    private static func basename(_ path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }

    /// The process's command line, from `KERN_PROCARGS2`: the argument count, the executable's path, then the
    /// arguments, each ending in a zero byte. Readable for your own processes.
    static func arguments(of pid: pid_t) -> [String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }
        let count = buffer.withUnsafeBytes { Int($0.loadUnaligned(as: Int32.self)) }
        var index = MemoryLayout<Int32>.size
        // Skip the executable's path and the zero bytes after it.
        while index < size, buffer[index] != 0 { index += 1 }
        while index < size, buffer[index] == 0 { index += 1 }
        var arguments: [String] = []
        while arguments.count < count, index < size {
            let start = index
            while index < size, buffer[index] != 0 { index += 1 }
            arguments.append(String(decoding: buffer[start..<index], as: UTF8.self))
            index += 1
        }
        return arguments
    }
}
