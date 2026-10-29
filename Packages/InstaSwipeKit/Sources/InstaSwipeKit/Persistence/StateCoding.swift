import Foundation

public enum StateCoding {
    private static let fractionalStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let plainStyle = Date.ISO8601FormatStyle()

    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(fractionalStyle))
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    /// Accepts dates with and without fractional seconds (older files have none).
    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = try? fractionalStyle.parse(string) { return date }
            if let date = try? plainStyle.parse(string) { return date }
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Invalid ISO 8601 date: \(string)")
        }
        return decoder
    }
}
