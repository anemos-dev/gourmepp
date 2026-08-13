import SwiftData
import SwiftUI
import UIKit

struct ProPhotoMemoriesView: View {
    @Environment(ProPreferences.self) private var proPreferences
    @Query private var records: [RestaurantRecord]
    @Query private var places: [Place]
    @Query private var photos: [RecordPhoto]
    @State private var selectedYear = Calendar.current.component(.year, from: .now)
    @State private var selectedMonth: Int?
    @State private var sharedCollage: SharedPhotoCollage?

    private var availableYears: [Int] {
        let years = records.compactMap(\.visitDate).map { Calendar.current.component(.year, from: $0) }
        return Array(Set(years + [Calendar.current.component(.year, from: .now)])).sorted(by: >)
    }
    private var memoryItems: [PhotoMemoryItem] {
        let recordByID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        let placeByID = Dictionary(uniqueKeysWithValues: places.map { ($0.id, $0) })
        return photos.compactMap { photo in
            guard let record = recordByID[photo.recordID],
                  !record.isDeleted,
                  record.status == .visited,
                  let date = record.visitDate,
                  Calendar.current.component(.year, from: date) == selectedYear,
                  selectedMonth == nil || Calendar.current.component(.month, from: date) == selectedMonth,
                  let image = LocalPhotoStore().image(at: photo.thumbnailPath)
            else { return nil }
            return PhotoMemoryItem(
                id: photo.id,
                recordID: record.id,
                date: date,
                placeName: placeByID[record.placeID]?.name ?? "店舗",
                image: image
            )
        }
        .sorted { $0.date > $1.date }
    }
    private var missingPhotoRecords: [RestaurantRecord] {
        let recordIDsWithPhotos = Set(photos.map(\.recordID))
        return records.filter { record in
            guard !record.isDeleted,
                  record.status == .visited,
                  !recordIDsWithPhotos.contains(record.id),
                  let date = record.visitDate,
                  Calendar.current.component(.year, from: date) == selectedYear
            else { return false }
            return selectedMonth == nil || Calendar.current.component(.month, from: date) == selectedMonth
        }
        .sorted { ($0.visitDate ?? .distantPast) > ($1.visitDate ?? .distantPast) }
    }
    private var collageTitle: String {
        if let selectedMonth { return "\(selectedYear)年\(selectedMonth)月" }
        return "\(selectedYear)年"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Picker("年", selection: $selectedYear) {
                        ForEach(availableYears, id: \.self) { Text(String($0) + "年").tag($0) }
                    }
                    Picker("月", selection: $selectedMonth) {
                        Text("1年").tag(Int?.none)
                        ForEach(1...12, id: \.self) { Text("\($0)月").tag(Optional($0)) }
                    }
                }
                .pickerStyle(.menu)

                VStack(alignment: .leading, spacing: 8) {
                    Text("PHOTO MEMORIES")
                        .font(.caption.bold())
                        .tracking(2)
                    Text(collageTitle)
                        .font(.largeTitle.bold())
                    Text("\(memoryItems.count)枚の写真を端末内で振り返ります")
                        .foregroundStyle(.secondary)
                }

                if memoryItems.isEmpty {
                    ContentUnavailableView(
                        "写真付きの記録がありません",
                        systemImage: "photo.on.rectangle.angled",
                        description: Text("期間を変えるか、訪問記録へ写真を追加してください。")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                } else {
                    PhotoCollagePreview(items: Array(memoryItems.prefix(9)))

                    Button(action: shareCollage) {
                        Label("この写真でコラージュを共有", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(proPreferences.accentColor)

                    Text("写真一覧")
                        .font(.headline)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 4)], spacing: 4) {
                        ForEach(memoryItems) { item in
                            NavigationLink {
                                PlaceDetailView(recordID: item.recordID)
                            } label: {
                                Image(uiImage: item.image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(minHeight: 110)
                                    .clipped()
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(item.placeName)、\(item.date.formatted(date: .long, time: .omitted))")
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                if !missingPhotoRecords.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("写真がない訪問記録", systemImage: "photo.badge.plus")
                            .font(.headline)
                        Text("\(missingPhotoRecords.count)件")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(missingPhotoRecords.prefix(5)) { record in
                            NavigationLink {
                                PlaceDetailView(recordID: record.id)
                            } label: {
                                HStack {
                                    Text(places.first { $0.id == record.placeID }?.name ?? "店舗")
                                    Spacer()
                                    Text(record.visitDate?.formatted(date: .abbreviated, time: .omitted) ?? "")
                                        .foregroundStyle(.secondary)
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if record.id != missingPhotoRecords.prefix(5).last?.id { Divider() }
                        }
                    }
                    .padding(18)
                    .background(.background)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
            .padding(16)
        }
        .background(Color("PinterestCanvas").ignoresSafeArea())
        .navigationTitle("写真の振り返り")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $sharedCollage) { collage in
            ShareSheet(items: [collage.image])
        }
    }

    private func shareCollage() {
        let images = memoryItems.prefix(9).map(\.image)
        guard let image = PhotoCollageRenderer.make(title: collageTitle, images: images) else { return }
        sharedCollage = SharedPhotoCollage(image: image)
    }
}

private struct PhotoMemoryItem: Identifiable {
    let id: UUID
    let recordID: UUID
    let date: Date
    let placeName: String
    let image: UIImage
}

private struct SharedPhotoCollage: Identifiable {
    let id = UUID()
    let image: UIImage
}

private struct PhotoCollagePreview: View {
    let items: [PhotoMemoryItem]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(items) { item in
                Image(uiImage: item.image)
                    .resizable()
                    .scaledToFill()
                    .frame(minHeight: 105)
                    .clipped()
                    .accessibilityLabel(item.placeName)
            }
        }
        .padding(8)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

@MainActor
enum PhotoCollageRenderer {
    static func make(title: String, images: [UIImage]) -> UIImage? {
        guard !images.isEmpty else { return nil }
        let size = CGSize(width: 1080, height: 1350)
        let margin: CGFloat = 54
        let gap: CGFloat = 12
        let headerHeight: CGFloat = 190
        let cell = (size.width - margin * 2 - gap * 2) / 3
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { context in
            UIColor(red: 0.97, green: 0.95, blue: 0.92, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))

            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .left
            ("ごはん日和  PHOTO MEMORIES" as NSString).draw(
                at: CGPoint(x: margin, y: 48),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 28, weight: .bold),
                    .foregroundColor: UIColor(red: 0.78, green: 0.32, blue: 0.05, alpha: 1),
                    .paragraphStyle: paragraph
                ]
            )
            (title as NSString).draw(
                at: CGPoint(x: margin, y: 96),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 58, weight: .black),
                    .foregroundColor: UIColor(red: 0.12, green: 0.10, blue: 0.09, alpha: 1),
                    .paragraphStyle: paragraph
                ]
            )

            for index in 0..<9 {
                let row = index / 3
                let column = index % 3
                let rect = CGRect(
                    x: margin + CGFloat(column) * (cell + gap),
                    y: headerHeight + CGFloat(row) * (cell + gap),
                    width: cell,
                    height: cell
                )
                if images.indices.contains(index) {
                    drawAspectFill(images[index], in: rect, context: context.cgContext)
                } else {
                    UIColor(red: 0.90, green: 0.86, blue: 0.80, alpha: 1).setFill()
                    context.fill(rect)
                }
            }

            ("記録は端末の中に。" as NSString).draw(
                at: CGPoint(x: margin, y: 1200),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 26, weight: .medium),
                    .foregroundColor: UIColor(red: 0.38, green: 0.34, blue: 0.31, alpha: 1)
                ]
            )
        }
    }

    private static func drawAspectFill(_ image: UIImage, in rect: CGRect, context: CGContext) {
        let scale = max(rect.width / image.size.width, rect.height / image.size.height)
        let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let drawRect = CGRect(
            x: rect.midX - drawSize.width / 2,
            y: rect.midY - drawSize.height / 2,
            width: drawSize.width,
            height: drawSize.height
        )
        context.saveGState()
        context.clip(to: rect)
        image.draw(in: drawRect)
        context.restoreGState()
    }
}
