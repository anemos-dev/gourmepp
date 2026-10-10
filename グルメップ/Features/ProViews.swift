import Charts
import SwiftData
import SwiftUI

struct AnnualFoodReportView: View {
    @Query private var records: [RestaurantRecord]
    @Query private var places: [Place]
    @Query private var tags: [Tag]
    @State private var selectedYear = Calendar.current.component(.year, from: .now)

    private var availableYears: [Int] {
        let recordedYears = records.compactMap(\.visitDate).map { Calendar.current.component(.year, from: $0) }
        return Array(Set(recordedYears + [Calendar.current.component(.year, from: .now)])).sorted(by: >)
    }

    private var report: AnnualFoodReport {
        AnnualFoodReport(year: selectedYear, records: records, places: places, tags: tags)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Picker("集計する年", selection: $selectedYear) {
                    ForEach(availableYears, id: \.self) { year in
                        Text(String(year) + "年").tag(year)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .trailing)

                ReportHero(report: report)

                if report.visitCount == 0 {
                    ContentUnavailableView(
                        "\(selectedYear)年の記録はありません",
                        systemImage: "calendar.badge.exclamationmark",
                        description: Text("訪問日を設定した「行った」記録が集計されます。")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    ReportMetrics(report: report)
                    MonthlyVisitsChart(monthlyCounts: report.monthlyCounts)
                    ReportHighlights(report: report)

                    ShareLink(item: report.shareText) {
                        Label("年間サマリーを共有", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(Color("BrandOrange"))
                }
            }
            .padding(16)
        }
        .themeScreenBackground()
        .navigationTitle("年間ごはんレポート")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ReportHero: View {
    let report: AnnualFoodReport

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MY FOOD YEAR")
                .font(.caption.weight(.bold))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.8))
            Text(String(report.year))
                .font(.system(size: 54, weight: .black, design: .rounded))
            Text(report.visitCount == 0 ? "次のおいしい記録を待っています" : "おいしい一年を振り返ろう")
                .font(.headline)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background(
            LinearGradient(
                colors: [Color("BrandSun"), Color("BrandOrange")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct ReportMetrics: View {
    let report: AnnualFoodReport
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ReportMetricCard(title: "訪問記録", value: "\(report.visitCount)件", icon: "fork.knife")
            ReportMetricCard(title: "訪れたお店", value: "\(report.uniquePlaceCount)店", icon: "storefront")
            ReportMetricCard(
                title: "平均評価",
                value: report.averageRating.map { String(format: "%.1f", $0) } ?? "—",
                icon: "star.fill"
            )
            ReportMetricCard(
                title: "一番多い月",
                value: report.busiestMonth.map { "\($0)月" } ?? "—",
                icon: "calendar"
            )
        }
    }
}

private struct ReportMetricCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct MonthlyVisitsChart: View {
    let monthlyCounts: [Int]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("月ごとの訪問").font(.headline)
            Chart(Array(monthlyCounts.enumerated()), id: \.offset) { index, count in
                BarMark(
                    x: .value("月", index + 1),
                    y: .value("訪問数", count)
                )
                .foregroundStyle(Color("BrandOrange").gradient)
                .cornerRadius(4)
                .accessibilityLabel("\(index + 1)月")
                .accessibilityValue("\(count)件")
            }
            .chartXAxis {
                AxisMarks(values: [1, 3, 5, 7, 9, 11]) { value in
                    AxisValueLabel { if let month = value.as(Int.self) { Text("\(month)月") } }
                }
            }
            .frame(height: 190)
        }
        .padding(18)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct ReportHighlights: View {
    let report: AnnualFoodReport

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("今年のハイライト").font(.headline)
            if let area = report.topArea {
                ReportHighlightRow(icon: "mappin.and.ellipse", title: "よく行ったエリア", value: "\(area.name)・\(area.count)件")
            }
            if let tag = report.topTag {
                ReportHighlightRow(icon: "tag.fill", title: "よく付けたタグ", value: "\(tag.name)・\(tag.count)件")
            }
            if !report.topRatedPlaces.isEmpty {
                Divider()
                Text("高評価のお店").font(.subheadline.weight(.semibold))
                ForEach(Array(report.topRatedPlaces.enumerated()), id: \.element.id) { index, place in
                    HStack {
                        Text("\(index + 1)").font(.headline).foregroundStyle(Color("BrandOrange"))
                        Text(place.name)
                        Spacer()
                        Text("★ \(String(format: "%.1f", place.rating))")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(18)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct ReportHighlightRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 28)
                .foregroundStyle(Color("BrandOrange"))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.headline)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct AnnualFoodReport {
    struct RankedValue: Identifiable, Equatable {
        let name: String
        let count: Int
        var id: String { name }
    }

    struct RatedPlace: Identifiable, Equatable {
        let id: UUID
        let name: String
        let rating: Double
    }

    let year: Int
    let visitCount: Int
    let uniquePlaceCount: Int
    let averageRating: Double?
    let busiestMonth: Int?
    let monthlyCounts: [Int]
    let topArea: RankedValue?
    let topTag: RankedValue?
    let topRatedPlaces: [RatedPlace]

    init(
        year: Int,
        records: [RestaurantRecord],
        places: [Place],
        tags: [Tag],
        calendar: Calendar = .current
    ) {
        self.year = year
        let visits = records.filter { record in
            guard !record.isTrashed,
                  record.status == .visited,
                  let visitDate = record.visitDate
            else { return false }
            return calendar.component(.year, from: visitDate) == year
        }
        let placeByID = Dictionary(uniqueKeysWithValues: places.map { ($0.id, $0) })
        let tagByID = Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0) })

        visitCount = visits.count
        uniquePlaceCount = Set(visits.map(\.placeID)).count

        let ratings = visits.map(\.displayRating).filter { $0 > 0 }
        averageRating = ratings.isEmpty ? nil : ratings.reduce(0, +) / Double(ratings.count)

        var months = Array(repeating: 0, count: 12)
        for visit in visits {
            guard let date = visit.visitDate else { continue }
            let month = calendar.component(.month, from: date)
            if (1...12).contains(month) { months[month - 1] += 1 }
        }
        monthlyCounts = months
        busiestMonth = months.max().flatMap { maximum in
            guard maximum > 0 else { return nil }
            return months.firstIndex(of: maximum).map { $0 + 1 }
        }

        let areas = visits.compactMap { visit -> String? in
            guard let place = placeByID[visit.placeID] else { return nil }
            return Place.municipality(from: place.address)
        }
        topArea = Self.mostFrequent(areas)

        let tagNames = visits.flatMap(\.tagIDs).compactMap { tagByID[$0]?.name }
        topTag = Self.mostFrequent(tagNames)

        let ratedByPlace = Dictionary(grouping: visits.filter { $0.displayRating > 0 }, by: \.placeID)
        topRatedPlaces = ratedByPlace.compactMap { placeID, placeVisits -> RatedPlace? in
            guard let place = placeByID[placeID] else { return nil }
            let rating = placeVisits.map(\.displayRating).reduce(0, +) / Double(placeVisits.count)
            return RatedPlace(id: placeID, name: place.name, rating: rating)
        }
        .sorted { left, right in
            if left.rating == right.rating { return left.name.localizedCompare(right.name) == .orderedAscending }
            return left.rating > right.rating
        }
        .prefix(5)
        .map { $0 }
    }

    var shareText: String {
        var lines = [
            "グルメップ \(year)年の記録",
            "訪問記録 \(visitCount)件・訪れたお店 \(uniquePlaceCount)店"
        ]
        if let averageRating { lines.append("平均評価 ★ \(String(format: "%.1f", averageRating))") }
        if let topArea { lines.append("よく行ったエリア：\(topArea.name)") }
        if let first = topRatedPlaces.first { lines.append("高評価のお店：\(first.name)") }
        return lines.joined(separator: "\n")
    }

    private static func mostFrequent(_ values: [String]) -> RankedValue? {
        let counts = Dictionary(values.map { ($0, 1) }, uniquingKeysWith: +)
        return counts
            .map { RankedValue(name: $0.key, count: $0.value) }
            .sorted { left, right in
                if left.count == right.count { return left.name.localizedCompare(right.name) == .orderedAscending }
                return left.count > right.count
            }
            .first
    }
}
