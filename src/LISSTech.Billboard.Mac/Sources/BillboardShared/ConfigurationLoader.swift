import Foundation

public struct BillboardLaunchRequest: Sendable {
    public var config: BillboardConfig
    public var resultFIFO: String?

    public init(config: BillboardConfig, resultFIFO: String? = nil) {
        self.config = config
        self.resultFIFO = resultFIFO
    }
}

public enum ConfigurationLoader {
    public static func load(arguments: [String] = Array(CommandLine.arguments.dropFirst())) throws -> BillboardLaunchRequest {
        var configData: Data?
        var resultFIFO: String?
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--payload":
                index += 1
                guard index < arguments.count,
                      let data = Data(base64Encoded: arguments[index]) else {
                    throw BillboardError.invalidConfiguration("--payload requires valid Base64 JSON.")
                }
                configData = data
            case "--config":
                index += 1
                guard index < arguments.count else {
                    throw BillboardError.invalidConfiguration("--config requires a file path.")
                }
                configData = try Data(contentsOf: URL(fileURLWithPath: arguments[index]), options: .mappedIfSafe)
            case "--json":
                configData = FileHandle.standardInput.readDataToEndOfFile()
            case "--result-fifo":
                index += 1
                guard index < arguments.count else {
                    throw BillboardError.invalidConfiguration("--result-fifo requires a path.")
                }
                resultFIFO = arguments[index]
            case "--help", "-h":
                throw BillboardError.invalidConfiguration(usage)
            default:
                throw BillboardError.invalidConfiguration("Unknown option: \(argument)\n\n\(usage)")
            }
            index += 1
        }

        guard let configData, !configData.isEmpty else {
            throw BillboardError.invalidConfiguration("A --payload, --config, or --json configuration is required.\n\n\(usage)")
        }

        var config = try BillboardJSON.decoder().decode(BillboardConfig.self, from: configData)
        try config.validateAndNormalize()
        return BillboardLaunchRequest(config: config, resultFIFO: resultFIFO)
    }

    public static let usage = """
    LISSTech Billboard for macOS

    GUI host:
      LISSTechBillboardMac --config /path/to/config.json
      LISSTechBillboardMac --payload <base64-json> [--result-fifo <path>]
      LISSTechBillboardMac --json

    RMM/root helper:
      lisstech-billboard-rmm --config /path/to/config.json
      lisstech-billboard-rmm --json
        [--app "/Applications/LISSTech Billboard.app/Contents/MacOS/LISSTechBillboardMac"]
        [--wait-seconds 3600]
    """
}
