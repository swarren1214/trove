import CloudKit
import Foundation
import Observation
import os
import UIKit

/// The vault: the family's assets, documents, scans and places, kept in their iCloud (the Hearth
/// container's `Trove` zone) with a copy on the device. Modeled on BigTable's kitchen.
///
/// Where it lives:
/// - Someone in their own household (or a household of one): their private database. When the
///   household has other parents and adults, it's shared with them (`TroveSharing`). Kids are
///   never in the zone; their documents are their parents'.
/// - Someone who joined another family's household: that family's vault, shared with them. What
///   they had comes along the first time.
///
/// It syncs on the household's engines (`HearthHouseholdStore`, as a `HearthZoneParticipant`),
/// so Trove never runs two engines on one database, and the other Hearth apps never download it.
@MainActor
@Observable
final class TroveStore: HearthZoneParticipant {
    static let shared = TroveStore()
    static let vaultZoneName = "Trove"
    let zoneName = TroveStore.vaultZoneName

    enum Location: Hashable {
        /// This account's own vault, in its private database.
        case personal
        /// Another family's vault this account was added to.
        case shared(ownerName: String)

        /// Each family's vault has its own files, so one family's data never reaches another's.
        var fileKey: String {
            switch self {
            case .personal: "personal"
            case .shared(let ownerName): "shared-" + ownerName.filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
            }
        }
    }

    private(set) var state = TroveState()
    private(set) var location: Location = .personal
    /// Goes up whenever iCloud brought changes, so screens can reload anything they cache.
    private(set) var revision = 0
    /// The last time iCloud sent or saved something for the vault.
    private(set) var lastSynced: Date?

    @ObservationIgnored private var systemFields: [String: Data] = [:]
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var started = false
    @ObservationIgnored private let log = Logger(subsystem: "com.stephenwarren.trove", category: "vault")

    /// Which family's vault this account joined (its zone owner), once accepted.
    private static let joinedOwnerKey = "vault.joinedOwner"

    var household: HearthHouseholdStore { .shared }

    // MARK: - Starting

    /// Call at launch, before the household store starts.
    func prepare() {
        guard !started else { return }
        started = true
        household.register(self)
        location = expectedLocation
        load()
    }

    private var expectedLocation: Location {
        if case .member(let ownerName) = household.mode,
           UserDefaults.standard.string(forKey: Self.joinedOwnerKey) == ownerName {
            return .shared(ownerName: ownerName)
        }
        return .personal
    }

    /// Follows the household: joined, left, or the vault's share accepted. Call when the
    /// household changes.
    func refreshLocation() {
        guard started else { return }
        // Left that family's household: their vault doesn't stay on this device.
        if case .shared(let ownerName) = location, household.mode != .member(ownerName: ownerName) {
            UserDefaults.standard.removeObject(forKey: Self.joinedOwnerKey)
            saveTask?.cancel()
            TroveFiles.remove(location.fileKey)
            state = TroveState()
            systemFields = [:]
            location = .personal
            load()
            queueEverything()
            cleanScans()
            revision += 1
        }
        let next = expectedLocation
        guard next != location else { return }
        log.notice("The vault moves to \(next.fileKey, privacy: .public)")
        let personal = location == .personal ? state : nil
        persistNow()
        location = next
        load()
        if case .shared(let ownerName) = next, let personal { bringAlong(personal, into: ownerName) }
        queueEverything()
        revision += 1
    }

    /// The first time someone joins a family's vault, what they had comes too.
    private func bringAlong(_ personal: TroveState, into ownerName: String) {
        let key = "vault.broughtAlong.\(ownerName)"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        let now = Date.now
        for (id, var place) in personal.places where state.places[id] == nil {
            place.updatedAt = now
            state.places[id] = place
        }
        for (id, var asset) in personal.assets where state.assets[id] == nil {
            asset.updatedAt = now
            state.assets[id] = asset
        }
        for (id, var document) in personal.documents where state.documents[id] == nil {
            document.updatedAt = now
            state.documents[id] = document
        }
        scheduleSave()
    }

    // MARK: - Zone

    var zoneLocation: (zoneID: CKRecordZone.ID, isShared: Bool)? {
        switch location {
        case .personal: (CKRecordZone.ID(zoneName: zoneName), false)
        case .shared(let ownerName): (CKRecordZone.ID(zoneName: zoneName, ownerName: ownerName), true)
        }
    }

    var isInFamilyVault: Bool {
        if case .shared = location { true } else { false }
    }

    // MARK: - Reading

    var assets: [TroveAsset] {
        state.assets.values.sorted { ($0.kind.rawValue, $0.name.localizedLowercase, $0.createdAt) < ($1.kind.rawValue, $1.name.localizedLowercase, $1.createdAt) }
    }

    var documents: [TroveDocument] {
        state.documents.values.sorted { ($0.type.group.rawValue, $0.displayTitle.localizedLowercase) < ($1.type.group.rawValue, $1.displayTitle.localizedLowercase) }
    }

    var places: [TrovePlace] {
        state.places.values.sorted { $0.name.localizedLowercase < $1.name.localizedLowercase }
    }

    func asset(_ id: String?) -> TroveAsset? { id.flatMap { state.assets[$0] } }
    func document(_ id: String?) -> TroveDocument? { id.flatMap { state.documents[$0] } }
    func place(_ id: String?) -> TrovePlace? { id.flatMap { state.places[$0] } }

    func documents(for owner: DocumentOwner) -> [TroveDocument] {
        documents.filter { $0.owner == owner }
    }

    func documents(inPlace placeID: String) -> [TroveDocument] {
        documents.filter { $0.placeID == placeID }
    }

    var documentsWithoutOriginal: [TroveDocument] {
        documents.filter(\.originalIsMissing)
    }

    /// Who or what a document belongs to, in words: "Ava", "2021 Highlander", "Household".
    func ownerName(_ owner: DocumentOwner) -> String {
        switch owner {
        case .person(let id): household.member(id)?.firstName ?? "Someone who left"
        case .asset(let id): asset(id)?.name ?? "A removed asset"
        case .household: household.info?.name ?? "Household"
        }
    }

    // MARK: - Changing

    func save(_ asset: TroveAsset) {
        var asset = asset
        asset.updatedAt = .now
        state.assets[asset.id] = asset
        changed(TroveRecords.assetName(asset.id))
    }

    /// Removes the asset and every document filed under it.
    func deleteAsset(_ id: String) {
        guard state.assets[id] != nil else { return }
        for document in documents(for: .asset(id)) { deleteDocument(document.id) }
        state.assets[id] = nil
        removed(TroveRecords.assetName(id))
    }

    /// Saves a document. `newScans` are pages captured for it: their files are written first,
    /// then everything is queued for iCloud.
    func save(_ document: TroveDocument, newScans: [(scan: TroveScan, data: Data)] = []) {
        var document = document
        for item in newScans where TroveFiles.writeScan(item.data, named: item.scan.fileName) {
            if !document.scans.contains(where: { $0.id == item.scan.id }) { document.scans.append(item.scan) }
            changed(TroveRecords.scanName(item.scan.id))
        }
        // Pages taken off the document lose their records too.
        let before = Set(state.documents[document.id]?.scans.map(\.id) ?? [])
        for gone in before.subtracting(document.scans.map(\.id)) {
            removed(TroveRecords.scanName(gone))
        }
        document.updatedAt = .now
        state.documents[document.id] = document
        changed(TroveRecords.documentName(document.id))
        cleanScansSoon()
    }

    func deleteDocument(_ id: String) {
        guard let document = state.documents[id] else { return }
        for scan in document.scans { removed(TroveRecords.scanName(scan.id)) }
        state.documents[id] = nil
        removed(TroveRecords.documentName(id))
        cleanScansSoon()
    }

    func save(_ place: TrovePlace) {
        var place = place
        place.updatedAt = .now
        state.places[place.id] = place
        changed(TroveRecords.placeName(place.id))
    }

    /// Removes the place. Its documents go back to "Location unknown".
    func deletePlace(_ id: String) {
        guard state.places[id] != nil else { return }
        for var document in documents(inPlace: id) {
            document.placeID = nil
            document.placeDetail = ""
            document.originalConfirmedAt = nil
            save(document)
        }
        state.places[id] = nil
        removed(TroveRecords.placeName(id))
    }

    /// Someone looked: everything in the place is still there.
    func confirmPlace(_ id: String) {
        guard var place = state.places[id] else { return }
        let now = Date.now
        place.confirmedAt = now
        save(place)
        for var document in documents(inPlace: id) {
            document.originalConfirmedAt = now
            save(document)
        }
    }

    /// Someone saw this original where Trove says it is.
    func confirmOriginal(_ documentID: String) {
        guard var document = state.documents[documentID] else { return }
        document.originalConfirmedAt = .now
        save(document)
    }

    /// Deletes everything in the vault, here and in iCloud (the owner's Erase App Data).
    func eraseEverything() {
        let names = state.assets.keys.map(TroveRecords.assetName)
            + state.documents.keys.map(TroveRecords.documentName)
            + state.documents.values.flatMap(\.scans).map { TroveRecords.scanName($0.id) }
            + state.places.keys.map(TroveRecords.placeName)
        state = TroveState()
        for name in names { removed(name) }
        persistNow()
        revision += 1
    }

    private func changed(_ recordName: String) {
        queue([.saveRecord(recordID(recordName))])
        scheduleSave()
    }

    private func removed(_ recordName: String) {
        systemFields[recordName] = nil
        queue([.deleteRecord(recordID(recordName))])
        scheduleSave()
    }

    private func recordID(_ name: String) -> CKRecord.ID {
        CKRecord.ID(recordName: name, zoneID: zoneLocation?.zoneID ?? CKRecordZone.ID(zoneName: zoneName))
    }

    private func queue(_ changes: [CKSyncEngine.PendingRecordZoneChange]) {
        guard let zone = zoneLocation else { return }
        if !zone.isShared { household.ensurePrivateZone(zone.zoneID) }
        household.queueZoneChanges(changes, isShared: zone.isShared)
    }

    private func queueEverything() {
        let names = state.places.keys.map(TroveRecords.placeName)
            + state.assets.keys.map(TroveRecords.assetName)
            + state.documents.keys.map(TroveRecords.documentName)
            + state.documents.values.flatMap(\.scans).filter(TroveFiles.hasScan).map { TroveRecords.scanName($0.id) }
        queue(names.map { .saveRecord(recordID($0)) })
    }

    /// Sends and fetches now (pull to refresh).
    func syncNow() async {
        guard let zone = zoneLocation else { return }
        await household.syncZoneNow(isShared: zone.isShared)
    }

    /// What the iCloud Sync card shows.
    var syncSnapshot: HearthSyncSnapshot {
        let account: HearthSyncSnapshot.Account = switch household.account {
        case .checking: .checking
        case .available: .available
        case .noAccount: .unavailable("Sign in to iCloud in Settings to keep your documents on all your devices.")
        case .unavailable: .unavailable(nil)
        }
        return HearthSyncSnapshot(
            account: account,
            isSyncing: household.isSyncing,
            lastSynced: lastSynced,
            pendingChanges: nil,
            errorMessage: household.problem
        )
    }

    // MARK: - HearthZoneParticipant

    func zoneRecord(for recordID: CKRecord.ID) -> CKRecord? {
        TroveRecords.record(named: recordID.recordName, in: state, base: cachedRecord(recordID), recordID: recordID)
    }

    func zoneFetched(modifications: [CKRecord], deletions: [CKDatabase.RecordZoneChange.Deletion]) {
        var next = state
        // A scan's image arriving changes the files, not the state; screens still redraw.
        var scansArrived = false
        for record in modifications {
            cache(record)
            if TroveRecords.merge(record, into: &next), record.recordType == "VaultScan" { scansArrived = true }
        }
        for deletion in deletions {
            let name = deletion.recordID.recordName
            systemFields[name] = nil
            TroveRecords.remove(named: name, from: &next)
        }
        if next != state || scansArrived {
            state = next
            revision += 1
        }
        lastSynced = .now
        scheduleSave()
    }

    func zoneSent(saved: [CKRecord], deleted: [CKRecord.ID], failedSaves: [CKSyncEngine.Event.SentRecordZoneChanges.FailedRecordSave], isShared: Bool) -> [CKSyncEngine.PendingRecordZoneChange] {
        for record in saved { cache(record) }
        var retry: [CKSyncEngine.PendingRecordZoneChange] = []
        for failure in failedSaves {
            let recordID = failure.record.recordID
            switch failure.error.code {
            case .serverRecordChanged:
                if let server = failure.error.serverRecord {
                    cache(server)
                    var next = state
                    // Theirs wins only when its own clock says it's newer.
                    if TroveRecords.merge(server, into: &next) {
                        state = next
                        revision += 1
                        continue
                    }
                }
                retry.append(.saveRecord(recordID))
            case .zoneNotFound:
                if isShared {
                    // The family stopped sharing the vault, or removed this person.
                    UserDefaults.standard.removeObject(forKey: Self.joinedOwnerKey)
                    refreshLocation()
                    return []
                }
                household.ensurePrivateZone(recordID.zoneID)
                systemFields[recordID.recordName] = nil
                retry.append(.saveRecord(recordID))
            case .unknownItem:
                systemFields[recordID.recordName] = nil
                retry.append(.saveRecord(recordID))
            case .batchRequestFailed:
                retry.append(.saveRecord(recordID))
            case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable, .requestRateLimited, .notAuthenticated, .operationCancelled, .accountTemporarilyUnavailable:
                break
            default:
                log.error("A vault save failed: \(failure.error.localizedDescription, privacy: .public)")
            }
        }
        if failedSaves.isEmpty, !(saved.isEmpty && deleted.isEmpty) { lastSynced = .now }
        scheduleSave()
        return retry
    }

    func zoneDatabaseChanged(added: [CKRecordZone.ID], deleted: [CKDatabase.DatabaseChange.Deletion], isShared: Bool) {
        guard isShared else {
            if deleted.contains(where: { $0.reason == .encryptedDataReset }), location == .personal {
                // The iCloud keys were reset: put back what's on this device.
                systemFields = [:]
                queueEverything()
            }
            return
        }
        if case .member(let ownerName) = household.mode, added.contains(where: { $0.ownerName == ownerName }) {
            // Accepted on another device, or by `TroveSharing.update`.
            markJoined(ownerName)
        }
        if case .shared(let ownerName) = location, deleted.contains(where: { $0.zoneID.ownerName == ownerName }) {
            UserDefaults.standard.removeObject(forKey: Self.joinedOwnerKey)
            refreshLocation()
        }
    }

    func markJoined(_ ownerName: String) {
        UserDefaults.standard.set(ownerName, forKey: Self.joinedOwnerKey)
        refreshLocation()
    }

    func zoneEngineReset(isShared: Bool) {
        refreshLocation()
        // The zone's records are as they were; the new engine just needs to know what to send.
        guard let zone = zoneLocation, zone.isShared == isShared else { return }
        queueEverything()
    }

    func zoneAccountDidChange() {
        UserDefaults.standard.removeObject(forKey: Self.joinedOwnerKey)
        TroveFiles.removeAll()
        systemFields = [:]
        state = TroveState()
        location = .personal
        lastSynced = nil
        revision += 1
    }

    // MARK: - Saving on the device

    private func load() {
        state = TroveFiles.loadState(location.fileKey) ?? TroveState()
        systemFields = TroveFiles.loadFields(location.fileKey)
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            persistNow()
        }
    }

    func persistNow() {
        saveTask?.cancel()
        TroveFiles.saveState(state, location.fileKey)
        TroveFiles.saveFields(systemFields, location.fileKey)
    }

    @ObservationIgnored private var cleanTask: Task<Void, Never>?

    private func cleanScansSoon() {
        cleanTask?.cancel()
        cleanTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            cleanScans()
        }
    }

    /// Deletes scan files no vault on this device still uses.
    private func cleanScans() {
        persistNow()
        let all = TroveFiles.allStates() + [state]
        let names = Set(all.flatMap { $0.documents.values.flatMap(\.scans).map(\.fileName) })
        TroveFiles.cleanScans(keeping: names)
    }

    private func cache(_ record: CKRecord) {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        systemFields[record.recordID.recordName] = coder.encodedData
    }

    private func cachedRecord(_ recordID: CKRecord.ID) -> CKRecord? {
        guard let data = systemFields[recordID.recordName],
              let coder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        coder.requiresSecureCoding = true
        defer { coder.finishDecoding() }
        guard let record = CKRecord(coder: coder), record.recordID.zoneID == recordID.zoneID else { return nil }
        return record
    }
}

// MARK: - Records

/// Vault values ↔ CloudKit records. Content is JSON in `encryptedValues`, so it's end-to-end
/// encrypted; a scan is its own record carrying the image as an asset.
nonisolated enum TroveRecords {
    static func assetName(_ id: String) -> String { "asset-" + id }
    static func documentName(_ id: String) -> String { "doc-" + id }
    static func placeName(_ id: String) -> String { "place-" + id }
    static func scanName(_ id: String) -> String { "scan-" + id }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .deferredToDate
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        return decoder
    }()

    /// The record to upload for `name`, or nil when the value is gone (or a scan's file hasn't
    /// arrived on this device).
    static func record(named name: String, in state: TroveState, base: CKRecord?, recordID: CKRecord.ID) -> CKRecord? {
        func make(_ type: String) -> CKRecord { base ?? CKRecord(recordType: type, recordID: recordID) }
        if let id = name.dropPrefix("asset-"), let asset = state.assets[id] {
            let record = make("VaultAsset")
            write(asset, updatedAt: asset.updatedAt, to: record)
            return record
        }
        if let id = name.dropPrefix("doc-"), let document = state.documents[id] {
            let record = make("VaultDocument")
            write(document, updatedAt: document.updatedAt, to: record)
            return record
        }
        if let id = name.dropPrefix("place-"), let place = state.places[id] {
            let record = make("VaultPlace")
            write(place, updatedAt: place.updatedAt, to: record)
            return record
        }
        if let id = name.dropPrefix("scan-"),
           let document = state.documents.values.first(where: { $0.scans.contains { $0.id == id } }),
           let scan = document.scans.first(where: { $0.id == id }) {
            let url = TroveFiles.scanURL(scan)
            guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
            let record = make("VaultScan")
            record.encryptedValues["documentID"] = document.id as NSString
            record["image"] = CKAsset(fileURL: url)
            record["updatedAt"] = scan.capturedAt as NSDate
            return record
        }
        return nil
    }

    private static func write(_ value: some Encodable, updatedAt: Date, to record: CKRecord) {
        record.encryptedValues["content"] = (try? encoder.encode(value)).map { $0 as NSData }
        record["updatedAt"] = updatedAt as NSDate
    }

    private static func content<T: Decodable>(_ type: T.Type, from record: CKRecord) -> T? {
        guard let data = record.encryptedValues["content"] as? Data else { return nil }
        return try? decoder.decode(type, from: data)
    }

    /// Takes in a fetched record when it's newer than what's here. Returns whether it did.
    @discardableResult
    static func merge(_ record: CKRecord, into state: inout TroveState) -> Bool {
        let name = record.recordID.recordName
        switch record.recordType {
        case "VaultAsset":
            guard let id = name.dropPrefix("asset-"), let incoming = content(TroveAsset.self, from: record),
                  incoming.updatedAt > (state.assets[id]?.updatedAt ?? .distantPast) else { return false }
            state.assets[id] = incoming
            return true
        case "VaultDocument":
            guard let id = name.dropPrefix("doc-"), let incoming = content(TroveDocument.self, from: record),
                  incoming.updatedAt > (state.documents[id]?.updatedAt ?? .distantPast) else { return false }
            state.documents[id] = incoming
            return true
        case "VaultPlace":
            guard let id = name.dropPrefix("place-"), let incoming = content(TrovePlace.self, from: record),
                  incoming.updatedAt > (state.places[id]?.updatedAt ?? .distantPast) else { return false }
            state.places[id] = incoming
            return true
        case "VaultScan":
            // The image arrives as an asset; keep it under the scan's own name. The scan's
            // details are on its document, which may arrive before or after.
            guard let id = name.dropPrefix("scan-"),
                  let asset = record["image"] as? CKAsset, let file = asset.fileURL,
                  let data = try? Data(contentsOf: file) else { return false }
            let target = TroveFiles.scanURL(named: "\(id).jpg")
            guard !FileManager.default.fileExists(atPath: target.path(percentEncoded: false)) else { return false }
            return TroveFiles.writeScan(data, named: "\(id).jpg")
        default:
            return false
        }
    }

    static func remove(named name: String, from state: inout TroveState) {
        if let id = name.dropPrefix("asset-") { state.assets[id] = nil }
        if let id = name.dropPrefix("doc-") { state.documents[id] = nil }
        if let id = name.dropPrefix("place-") { state.places[id] = nil }
        // A deleted scan record leaves its file until the document stops listing it.
    }
}

private extension String {
    nonisolated func dropPrefix(_ prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }
}
