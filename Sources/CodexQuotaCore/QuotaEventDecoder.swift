import Foundation

public struct DecodedRateLimitEvent: Equatable, Sendable {
    public struct Window: Equatable, Sendable {
        public let usedPercent: Double
        public let windowMinutes: Int
        public let resetsAt: Int64

        init(usedPercent: Double, windowMinutes: Int, resetsAt: Int64) {
            self.usedPercent = usedPercent
            self.windowMinutes = windowMinutes
            self.resetsAt = resetsAt
        }
    }

    public let observedAt: Date
    public let limitID: String
    public let primary: Window?
    public let secondary: Window?
}

public enum QuotaEventDecoder {
    public static func decode(line: String) -> DecodedRateLimitEvent? {
        guard
            let data = line.data(using: .utf8),
            let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
            envelope.type == "event_msg",
            let rateLimits = envelope.payload.rateLimits,
            let observedAt = parseTimestamp(envelope.timestamp)
        else {
            return nil
        }

        return .init(
            observedAt: observedAt,
            limitID: rateLimits.limitID,
            primary: rateLimits.primary.map(makeWindow),
            secondary: rateLimits.secondary.map(makeWindow)
        )
    }

    private static func makeWindow(_ window: Envelope.DecodedWindow) -> DecodedRateLimitEvent.Window {
        .init(
            usedPercent: window.usedPercent,
            windowMinutes: window.windowMinutes,
            resetsAt: window.resetsAt
        )
    }

    private static func parseTimestamp(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }

    private struct Envelope: Decodable {
        let timestamp: String
        let type: String
        let payload: Payload

        struct Payload: Decodable {
            let rateLimits: RateLimits?

            enum CodingKeys: String, CodingKey {
                case rateLimits = "rate_limits"
            }
        }

        struct RateLimits: Decodable {
            let limitID: String
            let primary: DecodedWindow?
            let secondary: DecodedWindow?

            enum CodingKeys: String, CodingKey {
                case limitID = "limit_id"
                case primary
                case secondary
            }
        }

        struct DecodedWindow: Decodable {
            let usedPercent: Double
            let windowMinutes: Int
            let resetsAt: Int64

            enum CodingKeys: String, CodingKey {
                case usedPercent = "used_percent"
                case windowMinutes = "window_minutes"
                case resetsAt = "resets_at"
            }
        }
    }
}
