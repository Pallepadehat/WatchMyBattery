import Foundation
import Testing

@testable import BatteryKit

/// 0.4.4: what comes in from the charger, and the GPU's part of each app's power.
@Suite struct PowerAttributionTests {
    // MARK: - The charger

    @Test func telemetrySaysWhatTheMacDrawsAndWhatComesIn() {
        let flow = SystemPowerReader.flow(telemetry: ["SystemLoad": 16741, "SystemPowerIn": 16741], millivolts: 12260, milliamps: 0)
        #expect(flow == PowerFlow(systemWatts: 16.741, chargerWatts: 16.741))
        // On battery nothing comes in.
        let onBattery = SystemPowerReader.flow(telemetry: ["SystemLoad": 9000, "SystemPowerIn": 0], millivolts: 12000, milliamps: -750)
        #expect(onBattery == PowerFlow(systemWatts: 9, chargerWatts: 0))
    }

    @Test func withoutTelemetryTheBatterysOutflowIsTheDraw() {
        let flow = SystemPowerReader.flow(telemetry: nil, millivolts: 12000, milliamps: -500)
        #expect(flow == PowerFlow(systemWatts: 6, chargerWatts: nil))
        #expect(SystemPowerReader.flow(telemetry: nil, millivolts: 12000, milliamps: 300) == nil)
        #expect(SystemPowerReader.flow(telemetry: ["SystemLoad": 0], millivolts: nil, milliamps: nil) == nil)
    }

    // MARK: - The GPU

    private typealias Client = GPUEnergySampler.GPUClient

    @Test func theGPUsEnergyIsSharedByTimeWorked() {
        let before: [UInt64: Client] = [1: Client(pid: 10, nanoseconds: 1_000), 2: Client(pid: 20, nanoseconds: 5_000)]
        let now: [UInt64: Client] = [1: Client(pid: 10, nanoseconds: 4_000), 2: Client(pid: 20, nanoseconds: 6_000)]
        let shares = GPUEnergySampler.share(joules: 2, now: now, before: before)
        #expect(shares[10] == 1.5)
        #expect(shares[20] == 0.5)
    }

    @Test func aProcesssConnectionsAddUpAndNewOnesCountInFull() {
        let before: [UInt64: Client] = [1: Client(pid: 10, nanoseconds: 1_000)]
        // Process 10 opened a second connection since; process 30 is new.
        let now: [UInt64: Client] = [
            1: Client(pid: 10, nanoseconds: 2_000), 2: Client(pid: 10, nanoseconds: 1_000), 3: Client(pid: 30, nanoseconds: 2_000),
        ]
        let shares = GPUEnergySampler.share(joules: 4, now: now, before: before)
        #expect(shares[10] == 2)
        #expect(shares[30] == 2)
    }

    @Test func noWorkNoShare() {
        let clients: [UInt64: Client] = [1: Client(pid: 10, nanoseconds: 1_000)]
        #expect(GPUEnergySampler.share(joules: 1, now: clients, before: clients).isEmpty)
        // A reused registry ID with another process starts afresh rather than going negative.
        let reused: [UInt64: Client] = [1: Client(pid: 11, nanoseconds: 500)]
        #expect(GPUEnergySampler.share(joules: 1, now: reused, before: clients) == [11: 1])
    }

    @Test func theCreatorNamesItsProcess() {
        #expect(GPUEnergySampler.pid(fromCreator: "pid 398, WindowServer") == 398)
        #expect(GPUEnergySampler.pid(fromCreator: "pid 0, kernel_task") == nil)
        #expect(GPUEnergySampler.pid(fromCreator: "WindowServer") == nil)
    }

    @Test func energyUnitsAreRead() {
        #expect(GPUEnergyCounter.joules(perUnit: "nJ") == 1e-9)
        #expect(GPUEnergyCounter.joules(perUnit: "mJ") == 1e-3)
        #expect(GPUEnergyCounter.joules(perUnit: "W") == nil)
    }
}

/// 0.4.4: commands run in a terminal, and programs running on their own, count as themselves.
@Suite struct OwnershipTests {
    /// A made-up process table: each process's parent, name and executable.
    private struct Table {
        var processes: [pid_t: (parent: pid_t, name: String, path: String)]

        func owner(of pid: pid_t, responsible: pid_t) -> pid_t {
            Ownership.owner(
                of: pid, responsible: responsible, parent: { processes[$0]?.parent }, name: { processes[$0]?.name },
                path: { processes[$0]?.path })
        }
    }

    // Terminal (100) → login (101) → zsh (102) → npm (103) → node (104) → esbuild (105); zsh idle in another tab (110).
    private let terminal = Table(processes: [
        100: (1, "Terminal", "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal"),
        101: (100, "login", "/usr/bin/login"),
        102: (101, "-zsh", "/bin/zsh"),
        103: (102, "npm", "/opt/homebrew/bin/node"),
        104: (103, "node", "/opt/homebrew/bin/node"),
        105: (104, "esbuild", "/project/node_modules/esbuild/bin/esbuild"),
        110: (101, "zsh", "/bin/zsh"),
    ])

    @Test func aTypedCommandOwnsEverythingItStarts() {
        #expect(terminal.owner(of: 103, responsible: 100) == 103)
        #expect(terminal.owner(of: 104, responsible: 100) == 103)
        #expect(terminal.owner(of: 105, responsible: 100) == 103)
    }

    @Test func theTerminalKeepsItsOwnProcessesAndIdleShells() {
        #expect(terminal.owner(of: 100, responsible: 100) == 100)
        #expect(terminal.owner(of: 101, responsible: 100) == 100)
        #expect(terminal.owner(of: 110, responsible: 100) == 100)
    }

    @Test func aShellInsideACommandDoesntSplitIt() {
        // `make` running a recipe through sh: still make.
        var table = terminal
        table.processes[120] = (102, "make", "/usr/bin/make")
        table.processes[121] = (120, "sh", "/bin/sh")
        table.processes[122] = (121, "clang", "/usr/bin/clang")
        #expect(table.owner(of: 122, responsible: 100) == 120)
    }

    @Test func aProgramRunningOnItsOwnOwnsItself() {
        // colima's host agent: started from Terminal, then adopted by launchd.
        let table = Table(processes: [
            200: (1, "limactl", "/opt/homebrew/bin/limactl"),
            201: (200, "ssh", "/usr/bin/ssh"),
        ])
        #expect(table.owner(of: 200, responsible: 100) == 200)
        #expect(table.owner(of: 201, responsible: 100) == 200)
    }

    @Test func anAppsServicesStayWithIt() {
        // Safari's web content, an XPC service launchd starts for it, and a helper inside its bundle.
        let table = Table(processes: [
            300: (
                1, "com.apple.WebKit.WebContent",
                "/System/Library/Frameworks/WebKit.framework/XPCServices/com.apple.WebKit.WebContent.xpc/Contents/MacOS/com.apple.WebKit.WebContent"
            ),
            301: (1, "Helper", "/Applications/Some.app/Contents/MacOS/Helper"),
            302: (999, "Renderer", "/Applications/Some.app/Contents/Frameworks/Renderer"),
        ])
        #expect(table.owner(of: 300, responsible: 400) == 400)
        #expect(table.owner(of: 301, responsible: 400) == 400)
        #expect(table.owner(of: 302, responsible: 999) == 999)
    }
}

@Suite struct CommandNameTests {
    @Test func aProgramIsNamedByItsExecutable() {
        #expect(CommandName.name(fromArguments: ["cargo", "build"], executable: "/Users/me/.cargo/bin/cargo") == "cargo")
        #expect(CommandName.name(fromArguments: ["-zsh"], executable: "/bin/zsh") == "zsh")
    }

    @Test func aScriptIsNamedRatherThanItsInterpreter() {
        #expect(CommandName.name(fromArguments: ["node", "/opt/homebrew/bin/npm", "run", "dev"], executable: "/opt/homebrew/bin/node") == "npm")
        #expect(
            CommandName.name(
                fromArguments: ["node", "--no-warnings", "/opt/homebrew/lib/node_modules/@anthropic-ai/claude-code/cli.js"],
                executable: "/opt/homebrew/bin/node") == "claude-code")
        #expect(CommandName.name(fromArguments: ["python3", "-m", "http.server", "8000"], executable: "/usr/bin/python3") == "http.server")
        #expect(
            CommandName.name(fromArguments: ["Python", "train.py"], executable: "/Library/Frameworks/Python.framework/Versions/3.12/bin/python3.12") == "train")
        #expect(CommandName.name(fromArguments: ["node", "/srv/api/dist/index.js"], executable: "/usr/local/bin/node") == "api")
        // Nothing but flags: the interpreter it is.
        #expect(CommandName.name(fromArguments: ["node", "--inspect"], executable: "/usr/local/bin/node") == "node")
    }

    @Test func ourOwnCommandLineIsRead() throws {
        let arguments = try #require(CommandName.arguments(of: getpid()))
        #expect(arguments.count == CommandLine.arguments.count)
    }
}

/// 0.4.4: macOS's own processes, from their CPU time.
@Suite struct CPUTimesTests {
    @Test func psTimesAreRead() {
        #expect(CPUTimes.seconds("12:49.93") == 769.93)
        #expect(CPUTimes.seconds("0:00.07") == 0.07)
        #expect(CPUTimes.seconds("1:02:03.50") == 3723.5)
        #expect(CPUTimes.seconds("2-01:00:00.00") == 176_400)
        #expect(CPUTimes.seconds("soon") == nil)
    }

    @Test func psOutputIsReadLineByLine() {
        let times = CPUTimes.parse("    1  12:51.36\n  250   0:00.07\nnonsense\n  325  10:46.02\n")
        #expect(times == [1: 771.36, 250: 0.07, 325: 646.02])
    }

    @Test func psRunsWithoutAdministratorRights() throws {
        let times = try #require(CPUTimes.read())
        // launchd, which belongs to root: exactly what the kernel won't show us directly.
        #expect((times[1] ?? 0) > 0)
    }

    @Test func calibrationFollowsWhatAppsUseWithinBounds() {
        var calibration = CPUEnergyCalibration()
        #expect(calibration.joulesPerCPUSecond == 1)
        for _ in 0..<50 { calibration.add(joules: 1.6, cpuSeconds: 1) }
        #expect(abs(calibration.joulesPerCPUSecond - 1.6) < 0.01)
        // A performance core flat out is more than background work would use: held to the top of the range.
        for _ in 0..<50 { calibration.add(joules: 9, cpuSeconds: 1) }
        #expect(abs(calibration.joulesPerCPUSecond - 2.5) < 0.01)
        // Too little to go by changes nothing.
        let before = calibration.joulesPerCPUSecond
        calibration.add(joules: 1, cpuSeconds: 0.001)
        #expect(calibration.joulesPerCPUSecond == before)
    }
}
