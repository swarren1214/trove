import Foundation
import OSLog
import UIKit
import UserNotifications

/// Expiry reminders and the yearly "is it still there?" check, as local notifications scheduled
/// on each device from the synced vault. Nothing goes through a server, and a notification never
/// carries a document's number: only the person's first name and the document type.
///
/// - Expiring: 9 AM on the day the lead time starts (passports nine months ahead, registrations
///   six weeks, see `DocumentType.defaultLeadDays`), again a week before, and on the day.
/// - Places: once a year after a place was last checked.
@MainActor
enum Reminders {
    private static let log = Logger(subsystem: "com.stephenwarren.trove", category: "reminders")
    private static let center = UNUserNotificationCenter.current()
    private static let prefix = "trove."
    private static var pending: Task<Void, Never>?

    /// At launch: show reminders while Trove is open, and open the document on a tap.
    static func start() {
        center.delegate = ReminderDelegate.shared
    }

    @discardableResult
    static func requestPermission() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            log.error("Couldn't ask for notifications: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    static func isDenied() async -> Bool {
        await center.notificationSettings().authorizationStatus == .denied
    }

    /// After changes, debounced.
    static func schedule() {
        pending?.cancel()
        pending = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await refresh()
        }
    }

    /// Brings every reminder up to date with the vault.
    static func refresh(now: Date = .now) async {
        let old = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: old)
        let defaults = UserDefaults.standard
        let store = TroveStore.shared
        let calendar = Calendar.current
        var requests: [(fire: Date, request: UNNotificationRequest)] = []

        if defaults.bool(forKey: SettingsKey.expiryReminders) {
            for document in store.documents {
                guard let expiry = document.expiryDate else { continue }
                let title = Attention.title(of: document, store: store)
                let lead = document.effectiveLeadDays
                let moments: [(daysBefore: Int, body: String)] = [
                    (lead, "Expires \(expiry.formatted(.dateTime.month(.wide).day().year())). Time to start renewing."),
                    (7, "Expires in a week, on \(expiry.formatted(.dateTime.weekday(.wide).month(.wide).day()))."),
                    (0, "Expires today."),
                ]
                for moment in moments where moment.daysBefore <= lead {
                    guard let day = calendar.date(byAdding: .day, value: -moment.daysBefore, to: expiry),
                          let fire = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day),
                          fire > now else { continue }
                    let content = UNMutableNotificationContent()
                    content.title = title
                    content.body = moment.body
                    content.sound = .default
                    content.threadIdentifier = "expiring"
                    content.userInfo = ["document": document.id]
                    let id = "\(prefix)doc.\(document.id).\(moment.daysBefore)"
                    let trigger = UNCalendarNotificationTrigger(dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire), repeats: false)
                    requests.append((fire, UNNotificationRequest(identifier: id, content: content, trigger: trigger)))
                }
            }
        }

        if defaults.bool(forKey: SettingsKey.placeReminders) {
            for place in store.places where !store.documents(inPlace: place.id).isEmpty {
                let checked = place.confirmedAt ?? place.createdAt
                guard let due = calendar.date(byAdding: .year, value: 1, to: checked),
                      let fire = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: max(due, calendar.date(byAdding: .day, value: 1, to: now) ?? now)),
                      fire > now else { continue }
                let content = UNMutableNotificationContent()
                content.title = "Is everything still in the \(place.name.localizedLowercase)?"
                content.body = "Take a quick look and tap Still There in Trove."
                content.sound = .default
                content.threadIdentifier = "places"
                content.userInfo = ["place": place.id]
                let trigger = UNCalendarNotificationTrigger(dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire), repeats: false)
                requests.append((fire, UNNotificationRequest(identifier: "\(prefix)place.\(place.id)", content: content, trigger: trigger)))
            }
        }

        // iOS keeps 64 pending notifications per app; the soonest matter most.
        for item in requests.sorted(by: { $0.fire < $1.fire }).prefix(50) {
            do { try await center.add(item.request) } catch {
                log.error("Couldn't schedule a reminder: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

/// Shows reminders while Trove is open, and routes a tap to the document or place.
nonisolated final class ReminderDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable {
    static let shared = ReminderDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let documentID = info["document"] as? String
        let placeID = info["place"] as? String
        await MainActor.run {
            if let documentID { AppRouter.shared.open(.document(documentID)) }
            if let placeID { AppRouter.shared.open(.place(placeID)) }
        }
    }
}
