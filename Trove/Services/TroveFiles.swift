import Foundation
import UIKit

/// The vault on the device: Application Support/Trove/<personal|shared-…>.json, the CloudKit
/// system fields beside it, and the scans in Application Support/Trove/Scans. Everything is
/// encrypted on the device until the first unlock after a restart (iCloud sync runs in the
/// background, so it has to be readable then); the app itself locks with Face ID.
nonisolated enum TroveFiles {
    private static var folder: URL {
        let url = URL.applicationSupportDirectory.appending(path: "Trove", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        excludeFromBackup(url)
        return url
    }

    static var scansFolder: URL {
        let url = folder.appending(path: "Scans", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Scans and the state are in iCloud already; device backups don't need another copy.
    private static func excludeFromBackup(_ url: URL) {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var url = url
        try? url.setResourceValues(values)
    }

    private static func stateURL(_ key: String) -> URL { folder.appending(path: "\(key).json", directoryHint: .notDirectory) }
    private static func fieldsURL(_ key: String) -> URL { folder.appending(path: "\(key)-fields.plist", directoryHint: .notDirectory) }

    static func loadState(_ key: String) -> TroveState? {
        guard let data = try? Data(contentsOf: stateURL(key)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        return try? decoder.decode(TroveState.self, from: data)
    }

    static func saveState(_ state: TroveState, _ key: String) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .deferredToDate
        guard let data = try? encoder.encode(state) else { return }
        try? data.write(to: stateURL(key), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func loadFields(_ key: String) -> [String: Data] {
        guard let data = try? Data(contentsOf: fieldsURL(key)),
              let fields = try? PropertyListDecoder().decode([String: Data].self, from: data) else { return [:] }
        return fields
    }

    static func saveFields(_ fields: [String: Data], _ key: String) {
        guard let data = try? PropertyListEncoder().encode(fields) else { return }
        try? data.write(to: fieldsURL(key), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func remove(_ key: String) {
        try? FileManager.default.removeItem(at: stateURL(key))
        try? FileManager.default.removeItem(at: fieldsURL(key))
    }

    static func removeAll() {
        try? FileManager.default.removeItem(at: folder)
    }

    /// Every vault saved on this device (the person's own, and a family's they joined).
    static func allStates() -> [TroveState] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
        return names.filter { $0.hasSuffix(".json") }.compactMap { loadState(String($0.dropLast(5))) }
    }

    // MARK: Scans

    static func scanURL(_ scan: TroveScan) -> URL { scanURL(named: scan.fileName) }

    static func scanURL(named name: String) -> URL {
        scansFolder.appending(path: name, directoryHint: .notDirectory)
    }

    static func hasScan(_ scan: TroveScan) -> Bool {
        FileManager.default.fileExists(atPath: scanURL(scan).path(percentEncoded: false))
    }

    static func scanData(_ scan: TroveScan) -> Data? {
        try? Data(contentsOf: scanURL(scan))
    }

    static func scanImage(_ scan: TroveScan) -> UIImage? {
        scanData(scan).flatMap(UIImage.init(data:))
    }

    @discardableResult
    static func writeScan(_ data: Data, named name: String) -> Bool {
        guard !name.contains("/") else { return false }
        return (try? data.write(to: scanURL(named: name), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])) != nil
    }

    /// Deletes scan files no document on this device uses.
    static func cleanScans(keeping names: Set<String>) {
        let folder = scansFolder
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)) else { return }
        for file in files where !names.contains(file) {
            try? FileManager.default.removeItem(at: folder.appending(path: file, directoryHint: .notDirectory))
        }
    }

    /// A captured page as the JPEG Trove keeps: full detail up to 2,400 px on the long side,
    /// so small print stays readable. Returns the data and its size.
    static func jpeg(from image: UIImage, maxSide: CGFloat = 2_400) -> (data: Data, width: Int, height: Int)? {
        let size = image.size
        let scale = min(1, maxSide / max(size.width, size.height, 1))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        guard let data = resized.jpegData(compressionQuality: 0.85) else { return nil }
        return (data, Int(target.width), Int(target.height))
    }
}
