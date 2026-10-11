//
//  GeneratedContent.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/08.
//

import Foundation
import FoundationModels

extension GeneratedContent:
    @retroactive ExpressibleByNilLiteral,
    @retroactive ExpressibleByBooleanLiteral,
    @retroactive ExpressibleByIntegerLiteral,
    @retroactive ExpressibleByFloatLiteral,
    @retroactive ExpressibleByStringLiteral,
    @retroactive ExpressibleByArrayLiteral,
    @retroactive ExpressibleByDictionaryLiteral
{
    public init(nilLiteral: ()) { self = .init(kind: .null) }
    public init(booleanLiteral value: Bool) { self = .init(kind: .bool(value)) }
    public init(integerLiteral value: Int) {
        self = .init(kind: .number(Double(value)))
    }
    public init(floatLiteral value: Double) {
        self = .init(kind: .number(value))
    }
    public init(stringLiteral value: String) {
        self = .init(kind: .string(value))
    }
    public init(arrayLiteral elements: GeneratedContent...) {
        self = .init(kind: .array(elements))
    }
    public init(dictionaryLiteral elements: (String, GeneratedContent)...) {
        let keys = elements.map(\.0)
        let dict: [String: GeneratedContent] = .init(
            uniqueKeysWithValues: elements
        )
        self = .init(kind: .structure(properties: dict, orderedKeys: keys))
    }
}

extension GeneratedContent: @retroactive Codable {

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .init(nilLiteral: ())
            return
        }
        if let v = try? c.decode(Bool.self) {
            self = .init(booleanLiteral: v)
            return
        }
        if let v = try? c.decode(Double.self) {
            self = .init(floatLiteral: v)
            return
        }
        if let v = try? c.decode(String.self) {
            self = .init(stringLiteral: v)
            return
        }
        if let v = try? c.decode([GeneratedContent].self) {
            self = .init(kind: .array(v))
            return
        }
        if let v = try? c.decode([String: GeneratedContent].self) {
            self = .init(
                kind: .structure(properties: v, orderedKeys: v.map(\.key))
            )
            return
        }
        throw DecodingError.dataCorruptedError(
            in: c,
            debugDescription: "Unsupported JSON value"
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self.kind {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .structure(properties: let v, orderedKeys: _): try c.encode(v)
        @unknown default:
            throw EncodingError.invalidValue(
                self,
                .init(
                    codingPath: [],
                    debugDescription: "Unsupported JSON value"
                )
            )
        }
    }
}

extension GeneratedContent {
    /// The named field of an object; `nil` for a missing field or a non-object.
    public subscript(field: String) -> GeneratedContent? {
        return try? self.value(forProperty: field)
    }

    /// Decodes the value into a `Decodable` type by round-tripping through
    /// `Data` — payload shapes are small, so clarity wins over speed.
    public func decoded<Value: Decodable>() -> Value? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }

    public static func encoded(_ value: some Encodable) -> GeneratedContent? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return try? JSONDecoder().decode(GeneratedContent.self, from: data)
    }

    public static func parsed(_ json: String) -> GeneratedContent? {
        try? JSONDecoder().decode(GeneratedContent.self, from: Data(json.utf8))
    }
}
