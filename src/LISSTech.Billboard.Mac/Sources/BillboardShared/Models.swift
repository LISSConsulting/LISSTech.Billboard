import Foundation

public enum NotificationType: String, Codable, CaseIterable, Sendable, Equatable {
    case info, warn, alert, critical, question

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self).lowercased()
        guard let result = Self(rawValue: value) else {
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "Invalid notification type: \(value)")
        }
        self = result
    }
}

public enum ThemeMode: String, Codable, CaseIterable, Sendable, Equatable {
    case auto, light, dark, starryNight, waterLilies, greatWave

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        guard let result = Self.allCases.first(where: {
            $0.rawValue.caseInsensitiveCompare(value) == .orderedSame
        }) else {
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "Invalid theme: \(value)")
        }
        self = result
    }
}

public enum BillboardButtonStyle: String, Codable, Sendable, Equatable {
    case ghost, primary, danger

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self).lowercased()
        guard let result = Self(rawValue: value) else {
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "Invalid button style: \(value)")
        }
        self = result
    }
}

public struct ButtonDefinition: Codable, Identifiable, Sendable {
    public var id: String { value }
    public var label: String
    public var value: String
    public var style: BillboardButtonStyle = .ghost
    public var deferSeconds: Double?

    public init(
        label: String,
        value: String,
        style: BillboardButtonStyle = .ghost,
        deferSeconds: Double? = nil
    ) {
        self.label = label
        self.value = value
        self.style = style
        self.deferSeconds = deferSeconds
    }

    private enum CodingKeys: String, CodingKey {
        case label, value, style
        case deferSeconds = "defer"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        label = try container.decode(String.self, forKey: .label)
        value = try container.decode(String.self, forKey: .value)
        style = try container.decodeIfPresent(BillboardButtonStyle.self, forKey: .style) ?? .ghost
        deferSeconds = try container.decodeIfPresent(Double.self, forKey: .deferSeconds)
    }
}

public struct InputDefinition: Codable, Sendable {
    public var label: String = "Response"
    public var placeholder: String?
    public var defaultValue: String?
    public var required: Bool = false
    public var multiline: Bool = false
    public var maxLength: Int = 1024

    public init(
        label: String = "Response",
        placeholder: String? = nil,
        defaultValue: String? = nil,
        required: Bool = false,
        multiline: Bool = false,
        maxLength: Int = 1024
    ) {
        self.label = label
        self.placeholder = placeholder
        self.defaultValue = defaultValue
        self.required = required
        self.multiline = multiline
        self.maxLength = maxLength
    }

    private enum CodingKeys: String, CodingKey {
        case label, placeholder, defaultValue, required, multiline, maxLength
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        label = try container.decodeIfPresent(String.self, forKey: .label) ?? "Response"
        placeholder = try container.decodeIfPresent(String.self, forKey: .placeholder)
        defaultValue = try container.decodeIfPresent(String.self, forKey: .defaultValue)
        required = try container.decodeIfPresent(Bool.self, forKey: .required) ?? false
        multiline = try container.decodeIfPresent(Bool.self, forKey: .multiline) ?? false
        maxLength = try container.decodeIfPresent(Int.self, forKey: .maxLength) ?? 1024
    }
}

public struct BrandingConfig: Codable, Sendable {
    public var name: String?
    public var logo: String?

    public init(name: String? = nil, logo: String? = nil) {
        self.name = name
        self.logo = logo
    }
}

public struct BillboardConfig: Codable, Sendable {
    public var type: NotificationType
    public var title: String
    public var message: String
    public var timeout: Int?
    public var modal: Bool = false
    public var theme: ThemeMode = .auto
    public var buttons: [ButtonDefinition] = []
    public var illustration: String?
    public var branding: BrandingConfig?
    public var input: InputDefinition?

    public init(
        type: NotificationType,
        title: String,
        message: String,
        timeout: Int? = nil,
        modal: Bool = false,
        theme: ThemeMode = .auto,
        buttons: [ButtonDefinition] = [],
        illustration: String? = nil,
        branding: BrandingConfig? = nil,
        input: InputDefinition? = nil
    ) {
        self.type = type
        self.title = title
        self.message = message
        self.timeout = timeout
        self.modal = modal
        self.theme = theme
        self.buttons = buttons
        self.illustration = illustration
        self.branding = branding
        self.input = input
    }

    private enum CodingKeys: String, CodingKey {
        case type, title, message, timeout, modal, theme, buttons, illustration, branding, input
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(NotificationType.self, forKey: .type)
        title = try container.decode(String.self, forKey: .title)
        message = try container.decode(String.self, forKey: .message)
        timeout = try container.decodeIfPresent(Int.self, forKey: .timeout)
        modal = try container.decodeIfPresent(Bool.self, forKey: .modal) ?? false
        theme = try container.decodeIfPresent(ThemeMode.self, forKey: .theme) ?? .auto
        buttons = try container.decodeIfPresent([ButtonDefinition].self, forKey: .buttons) ?? []
        illustration = try container.decodeIfPresent(String.self, forKey: .illustration)
        branding = try container.decodeIfPresent(BrandingConfig.self, forKey: .branding)
        input = try container.decodeIfPresent(InputDefinition.self, forKey: .input)
    }

    public var effectiveTimeout: Int {
        if let timeout { return timeout }
        switch type {
        case .info, .warn: return 10
        case .alert: return 15
        case .critical, .question: return 0
        }
    }

    public mutating func validateAndNormalize() throws {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BillboardError.invalidConfiguration("Title cannot be empty.")
        }
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BillboardError.invalidConfiguration("Message cannot be empty.")
        }
        guard effectiveTimeout >= 0 else {
            throw BillboardError.invalidConfiguration("Timeout cannot be negative.")
        }
        guard buttons.count <= 8 else {
            throw BillboardError.invalidConfiguration("At most eight buttons are supported.")
        }
        for button in buttons {
            guard !button.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !button.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw BillboardError.invalidConfiguration("Buttons require a label and value.")
            }
        }
        if type == .question && buttons.isEmpty {
            buttons = [ButtonDefinition(label: "OK", value: "ok", style: .primary)]
        }
        if let input {
            guard modal else {
                throw BillboardError.invalidConfiguration("Input is only supported in modal mode.")
            }
            guard !input.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw BillboardError.invalidConfiguration("Input label cannot be empty.")
            }
            guard (1...10_000).contains(input.maxLength) else {
                throw BillboardError.invalidConfiguration("Input maxLength must be between 1 and 10000.")
            }
            guard (input.defaultValue?.count ?? 0) <= input.maxLength else {
                throw BillboardError.invalidConfiguration("Input defaultValue exceeds maxLength.")
            }
        }
    }
}

public struct BillboardResult: Codable, Sendable {
    public var button: String?
    public var value: String?
    public var index: Int = -1
    public var dismissed: Bool = false
    public var timeout: Bool = false
    public var deferSeconds: Double?
    public var input: String?
    public var timestamp: Date = Date()

    private enum CodingKeys: String, CodingKey {
        case button, value, index, dismissed, timeout, input, timestamp
        case deferSeconds = "defer"
    }

    public init(
        button: String? = nil,
        value: String? = nil,
        index: Int = -1,
        dismissed: Bool = false,
        timeout: Bool = false,
        deferSeconds: Double? = nil,
        input: String? = nil,
        timestamp: Date = Date()
    ) {
        self.button = button
        self.value = value
        self.index = index
        self.dismissed = dismissed
        self.timeout = timeout
        self.deferSeconds = deferSeconds
        self.input = input
        self.timestamp = timestamp
    }
}

public enum BillboardError: LocalizedError {
    case invalidConfiguration(String)
    case transport(String)
    case image(String)

    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let message),
             .transport(let message),
             .image(let message):
            return message
        }
    }
}

public enum BillboardJSON {
    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .custom { codingPath in
            let key = codingPath.last!.stringValue
            let parts = key.split(separator: "_", omittingEmptySubsequences: true)
            guard let first = parts.first else {
                return BillboardCodingKey(stringValue: key)!
            }
            var normalized = first.prefix(1).lowercased() + String(first.dropFirst())
            for part in parts.dropFirst() {
                normalized += part.prefix(1).uppercased() + part.dropFirst().lowercased()
            }
            return BillboardCodingKey(stringValue: normalized)!
        }
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private struct BillboardCodingKey: CodingKey {
        let stringValue: String
        let intValue: Int?

        init?(stringValue: String) {
            self.stringValue = stringValue
            intValue = nil
        }

        init?(intValue: Int) {
            stringValue = String(intValue)
            self.intValue = intValue
        }
    }
}
