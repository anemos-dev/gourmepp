import Foundation
import Observation
import SwiftUI
import UIKit

struct SavedHomeFilter: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var query: String
    var statusRaw: String?
    var tagIDs: [UUID]
    var favoritesOnly: Bool
    var price: Int?
    var area: String
    var minimumRating: Double
    var hasPhotosOnly: Bool
}

enum ProAccentTheme: String, CaseIterable, Identifiable {
    case orange, red, green, blue

    var id: String { rawValue }
    var title: String {
        switch self {
        case .orange: "オレンジ"
        case .red: "朱色"
        case .green: "抹茶"
        case .blue: "藍色"
        }
    }
    var color: Color {
        switch self {
        case .orange: Color("BrandOrange")
        case .red: Color(red: 0.78, green: 0.18, blue: 0.12)
        case .green: Color(red: 0.20, green: 0.46, blue: 0.27)
        case .blue: Color(red: 0.15, green: 0.32, blue: 0.56)
        }
    }

    var highlightColor: Color {
        switch self {
        case .orange: Color("BrandSun")
        case .red: Color(red: 0.94, green: 0.36, blue: 0.25)
        case .green: Color(red: 0.36, green: 0.67, blue: 0.40)
        case .blue: Color(red: 0.30, green: 0.53, blue: 0.82)
        }
    }

    var canvasColor: Color {
        Color(uiColor: UIColor { traits in
            switch (self, traits.userInterfaceStyle) {
            case (.orange, .dark): UIColor(red: 0.13, green: 0.08, blue: 0.03, alpha: 1)
            case (.red, .dark): UIColor(red: 0.14, green: 0.05, blue: 0.04, alpha: 1)
            case (.green, .dark): UIColor(red: 0.04, green: 0.12, blue: 0.06, alpha: 1)
            case (.blue, .dark): UIColor(red: 0.03, green: 0.08, blue: 0.15, alpha: 1)
            case (.orange, _): UIColor(red: 1.00, green: 0.95, blue: 0.86, alpha: 1)
            case (.red, _): UIColor(red: 1.00, green: 0.92, blue: 0.90, alpha: 1)
            case (.green, _): UIColor(red: 0.91, green: 0.97, blue: 0.92, alpha: 1)
            case (.blue, _): UIColor(red: 0.90, green: 0.95, blue: 1.00, alpha: 1)
            }
        })
    }
}

@MainActor
@Observable
final class ProPreferences {
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let savedFiltersKey = "pro.savedHomeFilters"
    @ObservationIgnored private let accentKey = "pro.accentTheme"
    @ObservationIgnored private let gridColumnsKey = "pro.gridColumns"
    @ObservationIgnored private let cardDetailsKey = "pro.showsCardDetails"
    @ObservationIgnored private let defaultLayoutKey = "pro.defaultHomeLayout"

    var savedFilters: [SavedHomeFilter] {
        didSet { persistSavedFilters() }
    }
    var accentTheme: ProAccentTheme {
        didSet { defaults.set(accentTheme.rawValue, forKey: accentKey) }
    }
    var gridColumns: Int {
        didSet { defaults.set(gridColumns, forKey: gridColumnsKey) }
    }
    var showsCardDetails: Bool {
        didSet { defaults.set(showsCardDetails, forKey: cardDetailsKey) }
    }
    var defaultHomeLayoutRaw: String {
        didSet { defaults.set(defaultHomeLayoutRaw, forKey: defaultLayoutKey) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: savedFiltersKey),
           let decoded = try? JSONDecoder().decode([SavedHomeFilter].self, from: data) {
            savedFilters = decoded
        } else {
            savedFilters = []
        }
        accentTheme = ProAccentTheme(rawValue: defaults.string(forKey: accentKey) ?? "") ?? .orange
        let storedColumns = defaults.integer(forKey: gridColumnsKey)
        gridColumns = [2, 3, 4].contains(storedColumns) ? storedColumns : 2
        showsCardDetails = defaults.object(forKey: cardDetailsKey) == nil
            ? true
            : defaults.bool(forKey: cardDetailsKey)
        defaultHomeLayoutRaw = defaults.string(forKey: defaultLayoutKey) == "list" ? "list" : "grid"
    }

    var accentColor: Color { accentTheme.color }
    var highlightColor: Color { accentTheme.highlightColor }
    var canvasColor: Color { accentTheme.canvasColor }

    func save(_ filter: SavedHomeFilter) {
        savedFilters.removeAll { $0.name.localizedCaseInsensitiveCompare(filter.name) == .orderedSame }
        savedFilters.insert(filter, at: 0)
    }

    func deleteSavedFilters(at offsets: IndexSet) {
        savedFilters.remove(atOffsets: offsets)
    }

    #if DEBUG
    func resetToDefaults() {
        savedFilters = []
        accentTheme = .orange
        gridColumns = 2
        showsCardDetails = true
        defaultHomeLayoutRaw = "grid"
    }
    #endif

    private func persistSavedFilters() {
        guard let data = try? JSONEncoder().encode(savedFilters) else { return }
        defaults.set(data, forKey: savedFiltersKey)
    }
}
