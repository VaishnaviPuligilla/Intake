// Models.swift
// Contains application data models.
// Includes product lifecycle tracking and health insight logging.
// Designed for offline-first persistence using SwiftData.


import Foundation
import SwiftData
import SwiftUI


enum ProductState: String, Codable {
    case fresh
    case warning
    case alert
    case critical
    case expiredToday
    case expired
    case used
    case archived
}
enum PlantState: String, Codable {
    case fresh       // plant_img1
    case drying      // plant_img2
    case dead        // plant_img3
    case blooming    // plant_img4

    var imageName: String {
        switch self {
        case .fresh:    return "plant_img1"
        case .drying:   return "plant_img2"
        case .dead:     return "plant_img3"
        case .blooming: return "plant_img4"
        }
    }

    var stateColor: Color {
        switch self {
        case .fresh:    return Color(red: 0.20, green: 0.80, blue: 0.30)
        case .drying:   return Color(red: 0.95, green: 0.70, blue: 0.15)
        case .dead:     return Color(red: 0.60, green: 0.35, blue: 0.20)
        case .blooming: return Color(red: 0.30, green: 0.90, blue: 0.50)
        }
    }
}

@Model
final class ScannedItem {
    var id: UUID
    var productName: String
    var scanDate: Date
    var expiryDate: Date
    var imageData: Data?
    var isUsed: Bool
    var usedSuccessfully: Bool = false
    var isArchived: Bool = false
    var notificationsSent: Int = 0
    var lastNotificationDate: Date? = nil
    var acknowledgedByUser: Bool = false
    var reminderAt: Date? = nil
    /// Optional user choice: notify N days before expiry (1, 2, or 3).
    var notifyDaysBeforeExpiry: Int? = nil

    init(
        productName: String,
        scanDate: Date = Date(),
        expiryDate: Date,
        imageData: Data? = nil,
        isArchived: Bool = false
    ) {
        self.id                   = UUID()
        self.productName          = productName
        self.scanDate             = scanDate
        self.expiryDate           = expiryDate
        self.imageData            = imageData
        self.isUsed               = false
        self.usedSuccessfully     = false
        self.isArchived           = isArchived
        self.notificationsSent    = 0
        self.lastNotificationDate = nil
        self.acknowledgedByUser   = false
        self.reminderAt           = nil
        self.notifyDaysBeforeExpiry = nil
    }

    var daysRemaining: Int {
        let cal   = Calendar.current
        let start = cal.startOfDay(for: Date())
        let end   = cal.startOfDay(for: expiryDate)
        return cal.dateComponents([.day], from: start, to: end).day ?? 0
    }

    var isExpiredPastDate: Bool {
        return daysRemaining < 0
    }

    var shouldBeInHistory: Bool {
        return usedSuccessfully || (isArchived && daysRemaining < 0)
    }

    var productState: ProductState {
        if usedSuccessfully { return .used }
        if isArchived { return .archived }
        let d = daysRemaining
        switch d {
        case let x where x > 3: return .fresh
        case 3:                  return .warning
        case 2:                  return .alert
        case 1:                  return .critical
        case 0:                  return .expiredToday
        default:                 return .expired
        }
    }

    var plantState: PlantState {
        if usedSuccessfully { return .blooming }
        let d = daysRemaining
        if d > 3  { return .fresh   }
        if d >= 0 { return .drying  }
        return .dead
    }

    var statusTitle: String {
        let d = daysRemaining
        switch d {
        case let x where x > 3: return "\(x) days remaining"
        case 3:                 return "3 days remaining"
        case 2:                 return "2 days remaining"
        case 1:                 return "Expires tomorrow"
        case 0:                 return "Expires today"
        default:                return "Expired"
        }
    }

    var statusSubtext: String {
        let d = daysRemaining
        switch d {
        case let x where x > 5:
            let phrases = [
                "Still thriving.",
                "Safe and fresh.",
                "Plenty of time ahead.",
                "Growing well.",
                "Fresh for the next \(x) days."
            ]
            return phrases[abs(x) % phrases.count]
        case 4, 5: return "Looking good — use before it turns."
        case 3:    return "A gentle reminder — 3 days left."
        case 2:    return "Best used soon."
        case 1:    return "Use tomorrow, don't forget."
        case 0:    return "Last chance — today only."
        default:   return "Past its best."
        }
    }

    var statusColor: Color {
        switch productState {
        case .fresh:                  return Color(red: 0.20, green: 0.80, blue: 0.30)
        case .warning:                return Color(red: 0.65, green: 0.85, blue: 0.20)
        case .alert:                  return Color(red: 0.95, green: 0.70, blue: 0.15)
        case .critical:               return Color(red: 0.95, green: 0.52, blue: 0.12)
        case .expiredToday, .expired: return Color(red: 0.92, green: 0.28, blue: 0.15)
        case .used, .archived:        return Color(red: 0.55, green: 0.55, blue: 0.55)
        }
    }
}

@Model
final class HealthEntry {
    var id: UUID
    var productName: String
    var ingredientsText: String
    var riskLevel: String
    var loggedDate: Date
    var weekNumber: Int
    var yearNumber: Int

    init(productName: String, ingredientsText: String, riskLevel: String, loggedDate: Date = Date()) {
        self.id              = UUID()
        self.productName     = productName
        self.ingredientsText = ingredientsText
        self.riskLevel       = riskLevel
        self.loggedDate      = loggedDate
        let cal              = Calendar.current
        self.weekNumber      = cal.component(.weekOfYear, from: loggedDate)
        self.yearNumber      = cal.component(.yearForWeekOfYear, from: loggedDate)
    }
}
