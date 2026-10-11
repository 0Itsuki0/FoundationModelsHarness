//
//  JSONValue.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/11.
//

import Foundation
import FoundationModels

/// Loosely-typed JSON for tool inputs/outputs and schemas, where the shape
/// is determined at runtime.
public enum JSONValue: Sendable, Hashable, Codable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
            return
        }
        if let v = try? c.decode(Bool.self) {
            self = .bool(v)
            return
        }
        if let v = try? c.decode(Double.self) {
            self = .number(v)
            return
        }
        if let v = try? c.decode(String.self) {
            self = .string(v)
            return
        }
        if let v = try? c.decode([JSONValue].self) {
            self = .array(v)
            return
        }
        if let v = try? c.decode([String: JSONValue].self) {
            self = .object(v)
            return
        }
        throw DecodingError.dataCorruptedError(
            in: c,
            debugDescription: "Unsupported JSON value"
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }
}

extension JSONValue {
    /// The named field of an object; `nil` for a missing field or a non-object.
    public subscript(field: String) -> JSONValue? {
        if case .object(let fields) = self { fields[field] } else { nil }
    }

    /// Decodes the value into a `Decodable` type by round-tripping through
    /// `Data` — payload shapes are small, so clarity wins over speed.
    public func decoded<Value: Decodable>() -> Value? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }

    public static func encoded(_ value: some Encodable) -> JSONValue? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: data)
    }

    public static func parsed(_ json: String) -> JSONValue? {
        try? JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
    }
}

extension JSONValue: ExpressibleByNilLiteral, ExpressibleByBooleanLiteral,
    ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral,
    ExpressibleByStringLiteral, ExpressibleByArrayLiteral,
    ExpressibleByDictionaryLiteral
{
    public init(nilLiteral: ()) { self = .null }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
    public init(floatLiteral value: Double) { self = .number(value) }
    public init(stringLiteral value: String) { self = .string(value) }
    public init(arrayLiteral elements: JSONValue...) {
        self = .array(elements)
    }
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(.init(uniqueKeysWithValues: elements))
    }
}

extension JSONValue {
    public static func from(generatedContent: GeneratedContent) throws
        -> JSONValue
    {
        switch generatedContent.kind {
        case .null: return .null
        case .bool(let v): return .bool(v)
        case .number(let v): return .number(v)
        case .string(let v): return .string(v)
        case .array(let v): return try .array(v.map(JSONValue.from))
        case .structure(properties: let v, orderedKeys: _):
            return try .object(v.mapValues(JSONValue.from))
        @unknown default:
            throw EncodingError.invalidValue(
                self,
                .init(
                    codingPath: [],
                    debugDescription: "Unsupported GeneratedContent kind"
                )
            )
        }
    }

    public var generatedContent: GeneratedContent {
        switch self {
        case .null:
            return .init(kind: .null)
        case .bool(let value):
            return .init(kind: .bool(value))
        case .number(let value):
            return .init(kind: .number(Double(value)))
        case .string(let value):
            return .init(kind: .string(value))
        case .array(let value):
            return .init(kind: .array(value.map(\.generatedContent)))
        case .object(let value):
            return .init(
                kind: .structure(
                    properties: value.mapValues(\.generatedContent),
                    orderedKeys: value.map(\.key)
                )
            )
        }
    }
}
