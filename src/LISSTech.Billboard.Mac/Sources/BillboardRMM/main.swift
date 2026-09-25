import Darwin
import Foundation
import BillboardShared


@main
enum BillboardRMMMain {
    static func main() {
        do {
            let code = try run()
            Darwin.exit(code)
        } catch {
            FileHandle.standardError.write(Data("Billboard RMM: \(error.localizedDescription)\n".utf8))
            Darwin.exit(100)
        }
    }

    private static func run() throws -> Int32 {
        guard geteuid() == 0 else {
            throw BillboardError.transport("The RMM helper must run as root.")
        }

        var appPath = "/Applications/LISSTech Billboard.app/Contents/MacOS/LISSTechBillboardMac"
        var waitSeconds = 3600
        var configArguments: [String] = []
        let arguments = Array(CommandLine.arguments.dropFirst())
        var index = 0

        while index < arguments.count {
            switch arguments[index] {
            case "--app":
                index += 1
                guard index < arguments.count else {
                    throw BillboardError.invalidConfiguration("--app requires an executable path.")
                }
                appPath = arguments[index]
            case "--wait-seconds":
                index += 1
                guard index < arguments.count,
                      let value = Int(arguments[index]),
                      (1...3600).contains(value) else {
                    throw BillboardError.invalidConfiguration("--wait-seconds must be between 1 and 3600.")
                }
                waitSeconds = value
            default:
                configArguments.append(arguments[index])
                if ["--payload", "--config", "--result-fifo"].contains(arguments[index]) {
                    index += 1
                    guard index < arguments.count else {
                        throw BillboardError.invalidConfiguration("\(arguments[index - 1]) requires a value.")
                    }
                    configArguments.append(arguments[index])
                }
            }
            index += 1
        }

        guard FileManager.default.isExecutableFile(atPath: appPath) else {
            throw BillboardError.transport("Billboard app executable not found at \(appPath).")
        }

        let request = try ConfigurationLoader.load(arguments: configArguments)
        let consoleUser = try ConsoleSession.activeUser()
        let fifo = try ResultFIFO.createOwnedBy(uid: consoleUser.uid, gid: consoleUser.gid)
        defer { ResultFIFO.remove(fifo) }

        let configData = try BillboardJSON.encoder().encode(request.config)
        let payload = configData.base64EncodedString()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = [
            "asuser", String(consoleUser.uid),
            "/usr/bin/sudo", "-H", "-u", consoleUser.name,
            appPath,
            "--payload", payload,
            "--result-fifo", fifo
        ]
        var environment = ProcessInfo.processInfo.environment
        environment["HOME"] = consoleUser.home
        environment["USER"] = consoleUser.name
        environment["LOGNAME"] = consoleUser.name
        process.environment = environment
        try process.run()

        let resultData: Data
        do {
            resultData = try ResultFIFO.read(
                from: fifo,
                timeoutSeconds: waitSeconds,
                isPeerRunning: { process.isRunning })
        } catch {
            if process.isRunning {
                process.terminate()
            }
            throw error
        }
        process.waitUntilExit()

        let result = try BillboardJSON.decoder().decode(BillboardResult.self, from: resultData)
        FileHandle.standardOutput.write(resultData)
        FileHandle.standardOutput.write(Data([0x0A]))
        if result.timeout { return 2 }
        if result.dismissed { return 1 }
        return 0
    }

}
