//
//  ICloudCopy.swift
//  Wind Run
//
//  The copy of the runner's data in their private iCloud.
//

import CloudKit
import Foundation
import OSLog

/// Where this iPhone stands with iCloud, so Settings can say what's wrong in each case rather than calling
/// everything "signed out".
enum ICloudAccount: String {
    case available
    case signedOut
    /// Signed in, but iCloud needs the password again in the Settings app.
    case needsPassword
    /// Turned off for this iPhone, such as by Screen Time or the device's manager.
    case restricted
    /// iCloud couldn't say, such as with no connection.
    case unknown
}

/// What `WindRunStore` needs from iCloud. Tests and the simulator swap in a stand-in.
protocol ICloudCopy {
    /// Whether this iPhone is signed in to an iCloud account Wind Run can use.
    func accountIsAvailable() async -> Bool

    /// The same in more detail.
    func account() async -> ICloudAccount

    /// Deletes everything Wind Run has synced. Succeeds when there was nothing to delete.
    func delete() async throws
}

extension ICloudCopy {
    /// Stand-ins only say yes or no.
    func account() async -> ICloudAccount {
        await accountIsAvailable() ? .available : .signedOut
    }
}

/// The real copy, in the runner's private CloudKit database.
struct CloudKitCopy: ICloudCopy {
    // The zone SwiftData's CloudKit mirroring writes every record to.
    private static let zoneID = CKRecordZone.ID(zoneName: "com.apple.coredata.cloudkit.zone")

    private var container: CKContainer {
        CKContainer(identifier: WindRunSchema.cloudKitContainerID)
    }

    func accountIsAvailable() async -> Bool {
        await account() == .available
    }

    func account() async -> ICloudAccount {
        let status: CKAccountStatus
        do {
            status = try await container.accountStatus()
        } catch {
            Trace.error("iCloud account status", error)
            return .unknown
        }
        Trace.log(.icloud, "Account status", ["status": status.rawValue])
        return switch status {
        case .available: .available
        case .noAccount: .signedOut
        case .temporarilyUnavailable: .needsPassword
        case .restricted: .restricted
        case .couldNotDetermine: .unknown
        @unknown default: .unknown
        }
    }

    func delete() async throws {
        do {
            try await container.privateCloudDatabase.deleteRecordZone(withID: Self.zoneID)
        } catch let error as CKError where Self.meansNothingToDelete(error) {
            // Nothing was uploaded yet, or the runner already deleted it in iOS Settings.
        }
    }

    static func meansNothingToDelete(_ error: CKError) -> Bool {
        error.code == .zoneNotFound || error.code == .userDeletedZone
    }
}

#if DEBUG
/// Stands in for iCloud in previews, and in the simulator where nobody is signed in.
///
/// Run from Xcode with `-fakeICloud signedIn` to try iCloud sync's screens, or
/// `-fakeICloud unreachable` to see what happens when the iCloud copy can't be deleted.
struct FakeICloud: ICloudCopy {
    enum Mode: String {
        case signedIn
        case signedOut
        case unreachable
    }

    /// The mode picked with the `-fakeICloud` launch argument, if any.
    static var requestedMode: Mode? {
        UserDefaults.standard.string(forKey: "fakeICloud").flatMap(Mode.init(rawValue:))
    }

    let mode: Mode

    func accountIsAvailable() async -> Bool {
        mode != .signedOut
    }

    func delete() async throws {
        // Long enough to see the "Deleting" state.
        try await Task.sleep(for: .seconds(1.5))
        guard mode == .signedIn else { throw CKError(.networkUnavailable) }
        Logger.persistence.info("Pretended to delete the iCloud copy")
    }
}
#endif
