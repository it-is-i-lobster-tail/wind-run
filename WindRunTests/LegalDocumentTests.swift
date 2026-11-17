//
//  LegalDocumentTests.swift
//  Wind Run Tests
//

import Foundation
import Testing
@testable import WindRun

/// The privacy policy and terms in Settings → Legal say exactly what `PRIVACY.md` and `TERMS.md` at the top
/// of the repository say, so the copy people read on GitHub is the one in the app.
struct LegalDocumentTests {
    /// The repository's top folder, found from this file. Simulator tests can read the Mac's files.
    private static let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    @Test(arguments: [
        (LegalDocument.privacyPolicy, "PRIVACY.md"),
        (LegalDocument.termsAndConditions, "TERMS.md"),
    ])
    func appMatchesRepositoryFile(document: LegalDocument, file: String) throws {
        let text = try String(contentsOf: Self.repository.appending(path: file), encoding: .utf8)
        #expect(text == Self.markdown(for: document))
    }

    @Test func eachDocumentHasSections() {
        for document in [LegalDocument.privacyPolicy, .termsAndConditions] {
            #expect(!document.sections.isEmpty)
            #expect(Set(document.sections.map(\.heading)).count == document.sections.count)
            #expect(document.sections.allSatisfy { !$0.body.isEmpty })
        }
    }

    /// The markdown file a document is kept as: its title, the date, then each section under its heading.
    static func markdown(for document: LegalDocument) -> String {
        var lines = ["# Wind Run \(document.title)", "", "Last updated: \(document.lastUpdated)", ""]
        for section in document.sections {
            lines += ["## \(section.heading)", "", section.body, ""]
        }
        return lines.joined(separator: "\n")
    }
}
