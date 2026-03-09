// NotificationManager.swift
// Handles local user notification scheduling, cancellation, and delivery control.
// Supports expiry reminders for scanned products.
// Works with permission-safe asynchronous scheduling.

import Foundation
import UserNotifications

enum NotificationScheduleResult {
    case scheduled
    case immediate
    case noReminder
    case permissionDenied
}

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }
    private let defaults = UserDefaults.standard
    func requestPermission(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .badge, .sound]
        ) { granted, _ in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    func scheduleNotifications(
        for item: ScannedItem,
        reminderAt: Date?,
        completion: ((NotificationScheduleResult) -> Void)? = nil
    ) {
        cancelNotifications(for: item)

        guard let reminderAt else {
            DispatchQueue.main.async { completion?(.noReminder) }
            return
        }
        ensureAuthorization { [weak self] granted in
            guard granted, let self else {
                print("Notification permission denied; cannot schedule for \(item.productName)")
                completion?(.permissionDenied)
                return
            }

            let now = Date()
            if reminderAt <= now.addingTimeInterval(5) {
                self.sendImmediate(
                    for: item,
                    body: "Reminder: \(item.productName) is nearing expiry. Please check it."
                )
                DispatchQueue.main.async { completion?(.immediate) }
                return
            }

            self.scheduleOneNotification(
                for: item,
                at: reminderAt,
                identifier: "\(item.id.uuidString)-custom-reminder",
                body: "Reminder: \(item.productName) is nearing expiry. Please check it."
            )
            self.logPendingNotification(for: item)
            DispatchQueue.main.async { completion?(.scheduled) }
        }
    }

    private func ensureAuthorization(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                DispatchQueue.main.async { completion(true) }
            case .notDetermined:
                self.requestPermission(completion: completion)
            case .denied:
                DispatchQueue.main.async { completion(false) }
            @unknown default:
                DispatchQueue.main.async { completion(false) }
            }
        }
    }

    private func scheduleOneNotification(
        for item: ScannedItem,
        at fireDate: Date,
        identifier: String,
        body: String
    ) {
        let content = UNMutableNotificationContent()
        content.title = item.productName
        content.body  = body
        content.sound = .default
        content.userInfo = ["itemID": item.id.uuidString]

        let interval = max(1, fireDate.timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { err in
            if let err {
                print("Notification schedule error: \(err)")
                self.sendImmediate(
                    for: item,
                    body: "Reminder: \(item.productName) is nearing expiry. Please check it."
                )
            }
        }
    }

    private func sendImmediate(for item: ScannedItem, body: String) {
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let content = UNMutableNotificationContent()
        content.title = item.productName
        content.body  = body
        content.sound = .default
        content.userInfo = ["itemID": item.id.uuidString]
        let request = UNNotificationRequest(
            identifier: "\(item.id.uuidString)-immediate",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request) { err in
            if let err { print("Immediate notification error: \(err)") }
        }
    }

    func cancelNotifications(for item: ScannedItem) {
        let ids = notificationIdentifiers(for: item)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
    }

    func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    private func notificationIdentifiers(for item: ScannedItem) -> [String] {
        [
            "\(item.id.uuidString)-custom-reminder",
            "\(item.id.uuidString)-immediate"
        ]
    }

    private func logPendingNotification(for item: ScannedItem) {
        let ids = Set(notificationIdentifiers(for: item))
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let mine = requests.filter { ids.contains($0.identifier) }
            if mine.isEmpty {
                print("No pending notifications found for \(item.productName)")
            } else {
                for req in mine {
                    print("Pending notification: \(req.identifier)")
                }
            }
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        #if os(iOS)
        completionHandler([.banner, .list, .sound])
        #else
        completionHandler([.banner, .sound])
        #endif
    }
}
