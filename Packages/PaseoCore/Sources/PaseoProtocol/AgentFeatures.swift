import Foundation

// Provider-specific feature switches shown in the composer's agent controls: `toggle` (bool) and
// `select` (string|null out of a fixed option list). Source: messages.ts
// `AgentFeatureToggleSchema` / `AgentFeatureSelectSchema` / `AgentFeatureSchema` (:338–:362),
// carried on the snapshot `AgentSnapshotPayloadSchema.features` (messages.ts:887) and listed by
// `list_provider_features_request`.
//
// Forward compatibility: a feature of an unknown kind, or a known kind whose payload is
// malformed, decodes into `.unknown` — one bad feature never sinks a snapshot.

public enum AgentFeature: Sendable, Hashable, Decodable {
    case toggle(Toggle)
    case select(Select)
    /// A newer kind, or a known kind with a malformed payload. Kept for completeness; never
    /// rendered or toggled by the client.
    case unknown(type: String, raw: JSONValue)

    public struct Toggle: Sendable, Hashable, Decodable {
        public var id: String
        public var label: String
        public var description: String?
        public var tooltip: String?
        public var icon: String?
        public var value: Bool

        public init(
            id: String, label: String, description: String? = nil, tooltip: String? = nil,
            icon: String? = nil, value: Bool
        ) {
            self.id = id
            self.label = label
            self.description = description
            self.tooltip = tooltip
            self.icon = icon
            self.value = value
        }
    }

    public struct Select: Sendable, Hashable, Decodable {
        public var id: String
        public var label: String
        public var description: String?
        public var tooltip: String?
        public var icon: String?
        public var desktopTrigger: String?
        /// The selected option id, or nil for "no selection".
        public var value: String?
        public var options: [Option]

        public struct Option: Sendable, Hashable, Decodable {
            public var id: String
            public var label: String
            public var description: String?
            public var isDefault: Bool?

            public init(id: String, label: String, description: String? = nil, isDefault: Bool? = nil) {
                self.id = id
                self.label = label
                self.description = description
                self.isDefault = isDefault
            }
        }

        public init(
            id: String, label: String, description: String? = nil, tooltip: String? = nil,
            icon: String? = nil, desktopTrigger: String? = nil, value: String?, options: [Option]
        ) {
            self.id = id
            self.label = label
            self.description = description
            self.tooltip = tooltip
            self.icon = icon
            self.desktopTrigger = desktopTrigger
            self.value = value
            self.options = options
        }
    }

    /// Never throws: every shape decodes into `.unknown` on any mismatch, so one bad feature
    /// never sinks a snapshot.
    public init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode(JSONValue.self)) ?? .null
        guard case .object = raw else {
            self = .unknown(type: "invalid", raw: raw)
            return
        }
        guard let type = raw["type"]?.stringValue else {
            self = .unknown(type: "invalid", raw: raw)
            return
        }

        switch type {
        case "toggle": self = (try? raw.decoded(as: Toggle.self)).map(AgentFeature.toggle)
            ?? .unknown(type: type, raw: raw)
        case "select": self = (try? raw.decoded(as: Select.self)).map(AgentFeature.select)
            ?? .unknown(type: type, raw: raw)
        default: self = .unknown(type: type, raw: raw)
        }
    }
}

public extension AgentFeature {
    /// The wire id, empty for `.unknown` (callers must skip those).
    var id: String {
        switch self {
        case .toggle(let toggle): toggle.id
        case .select(let select): select.id
        case .unknown: ""
        }
    }

    /// The human label, empty for `.unknown`.
    var label: String {
        switch self {
        case .toggle(let toggle): toggle.label
        case .select(let select): select.label
        case .unknown: ""
        }
    }

    var descriptionText: String? {
        switch self {
        case .toggle(let toggle): toggle.description
        case .select(let select): select.description
        case .unknown: nil
        }
    }

    /// The current value as a plain string ("true"/"false" for toggles), nil for unknown/no value.
    var valueText: String? {
        switch self {
        case .toggle(let toggle): "\(toggle.value)"
        case .select(let select): select.value
        case .unknown: nil
        }
    }

    /// Applies a value; nil when the value doesn't fit this feature (wrong kind, or a select
    /// option id the feature doesn't offer).
    func applying(value: JSONValue) -> AgentFeature? {
        switch (self, value) {
        case (.toggle(var toggle), .bool(let on)):
            toggle.value = on
            return .toggle(toggle)
        case (.select(var select), .string(let optionId)):
            guard select.options.contains(where: { $0.id == optionId }) else { return nil }
            select.value = optionId
            return .select(select)
        case (.select(var select), .null):
            select.value = nil
            return .select(select)
        default:
            return nil
        }
    }
}

