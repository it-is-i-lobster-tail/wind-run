import CoreData
import Foundation
import SwiftData
import XCTest
@testable import WindRun

final class CloudKitSchemaTests: XCTestCase {
    @MainActor
    func testExportCloudKitFields() throws {
        let model = try XCTUnwrap(NSManagedObjectModel.makeManagedObjectModel(for: WindRunSchema.models))
        XCTAssertEqual(model.entities.count, WindRunSchema.models.count)
        let fields = try Self.cloudKitFields(for: model)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let attachment = XCTAttachment(data: try encoder.encode(fields), uniformTypeIdentifier: "public.json")
        attachment.name = "WindRunCloudKitFields"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // Use SwiftData's resolved Core Data model, including the storage types it chooses for Codable properties.
    // https://developer.apple.com/documentation/coredata/reading-cloudkit-records-for-core-data
    private static func cloudKitFields(for model: NSManagedObjectModel) throws -> [String: [String: String]] {
        var records: [String: [String: String]] = [:]
        for entity in model.entities {
            let name = try XCTUnwrap(entity.name)
            let root = sequence(first: entity, next: \.superentity).reduce(entity) { _, parent in parent }
            let recordType = "CD_\(try XCTUnwrap(root.name))"
            var fields = records[recordType, default: ["CD_entityName": "STRING QUERYABLE"]]
            for attribute in entity.attributesByName.values {
                try addAttribute(attribute, key: "CD_\(attribute.name)", encrypted: false, to: &fields)
            }
            for relationship in entity.relationshipsByName.values {
                let inverse = try XCTUnwrap(relationship.inverseRelationship, "Missing inverse for \(name).\(relationship.name)")
                if !relationship.isToMany {
                    try addField("CD_\(relationship.name)", type: "STRING QUERYABLE", to: &fields)
                } else if inverse.isToMany {
                    records["CDMR"] = [
                        "CD_entityNames": "STRING QUERYABLE",
                        "CD_recordNames": "STRING QUERYABLE",
                        "CD_relationships": "STRING QUERYABLE",
                    ]
                }
            }
            records[recordType] = fields
        }
        return records
    }

    private static func addAttribute(
        _ attribute: NSAttributeDescription,
        key: String,
        encrypted: Bool,
        to fields: inout [String: String]
    ) throws {
        if attribute.isTransient { return }
        let encrypted = encrypted || attribute.allowsCloudEncryption
        if let composite = attribute as? NSCompositeAttributeDescription {
            // SwiftData represents a raw-value enum as one storage attribute with the property's name.
            guard composite.elements.count == 1, let element = composite.elements.first,
                  element.name == attribute.name, !(element is NSCompositeAttributeDescription) else {
                throw SchemaError.unsupportedAttribute(key, attribute.attributeType.rawValue)
            }
            try addAttribute(element, key: key, encrypted: encrypted, to: &fields)
            return
        }
        let type: String
        switch attribute.attributeType {
        case .integer16AttributeType, .integer32AttributeType, .integer64AttributeType, .booleanAttributeType:
            type = "INT64"
        case .decimalAttributeType, .doubleAttributeType, .floatAttributeType:
            type = "DOUBLE"
        case .dateAttributeType:
            type = "TIMESTAMP"
        case .UUIDAttributeType, .URIAttributeType:
            type = "STRING"
        case .stringAttributeType:
            type = "STRING"
            try addField("\(key)_ckAsset", type: "ASSET", to: &fields)
        case .binaryDataAttributeType, .transformableAttributeType:
            type = "BYTES"
            try addField("\(key)_ckAsset", type: "ASSET", to: &fields)
        default:
            throw SchemaError.unsupportedAttribute(key, attribute.attributeType.rawValue)
        }
        let storage = encrypted ? "ENCRYPTED \(type)" : type
        try addField(key, type: storage, to: &fields)
    }

    private static func addField(_ key: String, type: String, to fields: inout [String: String]) throws {
        if let existing = fields[key], existing != type {
            throw SchemaError.conflictingField(key, existing, type)
        }
        fields[key] = type
    }

    private enum SchemaError: Error {
        case unsupportedAttribute(String, UInt)
        case conflictingField(String, String, String)
    }
}
