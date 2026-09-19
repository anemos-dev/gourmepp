import SwiftUI
import UIKit

enum ShareCardTemplate: String, CaseIterable, Identifiable {
    case simple
    case editorial
    case collage
    case minimal
    case typography

    var id: String { rawValue }

    var title: String {
        switch self {
        case .simple: "シンプル"
        case .editorial: "エディトリアル"
        case .collage: "コラージュ"
        case .minimal: "ミニマル"
        case .typography: "タイポグラフィ"
        }
    }

    var detail: String {
        switch self {
        case .simple: "写真とお店の情報をすっきり配置"
        case .editorial: "写真を大きく見せる雑誌風デザイン"
        case .collage: "最大4枚の写真をリズムよく配置"
        case .minimal: "余白と繊細なセリフ体を活かしたデザイン"
        case .typography: "太い文字と高いコントラストのポスター風"
        }
    }

    var systemImage: String {
        switch self {
        case .simple: "rectangle.split.1x2"
        case .editorial: "text.below.photo"
        case .collage: "square.grid.2x2"
        case .minimal: "rectangle.inset.filled"
        case .typography: "textformat.size.larger"
        }
    }

    var requiresPro: Bool { self != .simple }
}

enum ShareCardFormat: String, CaseIterable, Identifiable {
    case portrait
    case square
    case landscape

    var id: String { rawValue }

    var title: String {
        switch self {
        case .portrait: "縦長 4:5"
        case .square: "正方形 1:1"
        case .landscape: "横長 16:9"
        }
    }

    var detail: String {
        switch self {
        case .portrait: "Instagram・X"
        case .square: "Instagram"
        case .landscape: "X"
        }
    }

    var pointSize: CGSize {
        switch self {
        case .portrait: CGSize(width: 360, height: 450)
        case .square: CGSize(width: 360, height: 360)
        case .landscape: CGSize(width: 400, height: 225)
        }
    }

    var pixelSize: CGSize {
        CGSize(width: pointSize.width * 3, height: pointSize.height * 3)
    }

    var requiresPro: Bool { self != .portrait }
}

enum ShareCardPalette: String, CaseIterable, Identifiable {
    case warm
    case sage
    case midnight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .warm: "ウォーム"
        case .sage: "セージ"
        case .midnight: "ミッドナイト"
        }
    }

    var background: Color {
        switch self {
        case .warm: Color(red: 0.98, green: 0.96, blue: 0.92)
        case .sage: Color(red: 0.90, green: 0.94, blue: 0.89)
        case .midnight: Color(red: 0.10, green: 0.12, blue: 0.16)
        }
    }

    var ink: Color { self == .midnight ? .white : Color(red: 0.12, green: 0.10, blue: 0.08) }

    var accent: Color {
        switch self {
        case .warm: Color(red: 0.70, green: 0.25, blue: 0.04)
        case .sage: Color(red: 0.16, green: 0.38, blue: 0.25)
        case .midnight: Color(red: 0.98, green: 0.63, blue: 0.18)
        }
    }

    var requiresPro: Bool { self != .warm }
}

enum ShareCardTextColor: String, CaseIterable, Identifiable {
    case black
    case white
    case orange

    var id: String { rawValue }

    var title: String {
        switch self {
        case .black: "黒"
        case .white: "白"
        case .orange: "オレンジ"
        }
    }

    var color: Color {
        switch self {
        case .black: Color(red: 0.12, green: 0.10, blue: 0.08)
        case .white: .white
        case .orange: Color("BrandOrange")
        }
    }
}

struct ShareCardContent {
    let placeName: String
    let category: String
    let area: String
    let rating: String?
    let memo: String?
    let visitDate: String?
    let tags: [String]
}

struct ShareCardOptions {
    var showsArea = true
    var showsRating = true
    var showsMemo = true
    var showsVisitDate = true
    var showsTags = true
}

struct ShareCardMakerView: View {
    @Environment(ProAccessController.self) private var proAccess

    let record: RestaurantRecord
    let place: Place
    let photos: [RecordPhoto]
    let tags: [Tag]

    @State private var template: ShareCardTemplate = .simple
    @State private var format: ShareCardFormat = .portrait
    @State private var palette: ShareCardPalette = .warm
    @State private var textColor: ShareCardTextColor = .black
    @State private var fontSizeOffset = 0
    @State private var selectedPhotoIDs: [UUID]
    @State private var options = ShareCardOptions()
    @State private var presentedSheet: ShareCardSheet?

    init(record: RestaurantRecord, place: Place, photos: [RecordPhoto], tags: [Tag]) {
        self.record = record
        self.place = place
        self.photos = photos.sorted { $0.order < $1.order }
        self.tags = tags
        _selectedPhotoIDs = State(initialValue: Array(self.photos.prefix(4).map(\.id)))
    }

    private var content: ShareCardContent {
        ShareCardContent(
            placeName: place.name,
            category: place.category,
            area: place.area.isEmpty ? Place.area(from: place.address) : place.area,
            rating: record.displayRating > 0 ? record.ratingText : nil,
            memo: record.memo.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            visitDate: record.visitDate?.formatted(date: .long, time: .omitted),
            tags: tags.filter { record.tagIDs.contains($0.id) }.map(\.name)
        )
    }

    private var selectedImages: [UIImage] {
        let store = LocalPhotoStore()
        return selectedPhotoIDs.compactMap { id in
            guard let photo = photos.first(where: { $0.id == id }) else { return nil }
            return store.image(at: photo.imagePath)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ShareCardPreview(
                    content: content,
                    images: selectedImages,
                    template: template,
                    format: format,
                    palette: palette,
                    textColor: textColor,
                    fontSizeOffset: fontSizeOffset,
                    options: options,
                    showsBranding: !proAccess.isProUnlocked
                )
                .frame(height: 430)
                .frame(maxWidth: .infinity)

                templateSection
                formatSection
                paletteSection
                textColorSection
                fontSizeSection
                photoSection
                informationSection

                Button(action: makeAndShareImage) {
                    Label("画像を共有・保存", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Color("BrandOrange"))

                Label("写真と記録は端末内で画像に変換され、共有するまで外部へ送信されません。", systemImage: "lock.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
        }
        .background(Color("PinterestCanvas").ignoresSafeArea())
        .navigationTitle("投稿画像を作る")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .paywall:
                ShareCardPaywallSheet()
            case .share(_, let image):
                ShareSheet(items: [image])
            }
        }
    }

    private var templateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("テンプレート", detail: "無料版ではシンプルを利用できます")
            ForEach(ShareCardTemplate.allCases) { candidate in
                Button {
                    select(candidate)
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: candidate.systemImage)
                            .font(.title3)
                            .frame(width: 32)
                            .foregroundStyle(candidate == template ? Color("BrandOrange") : .secondary)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(candidate.title).font(.headline)
                                if candidate.requiresPro {
                                    Text("PRO")
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color("BrandOrange").opacity(0.15))
                                        .foregroundStyle(Color("BrandOrange"))
                                        .clipShape(Capsule())
                                }
                            }
                            Text(candidate.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: candidate.requiresPro && !proAccess.isProUnlocked ? "lock.fill" : candidate == template ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(candidate == template ? Color("BrandOrange") : .secondary)
                    }
                    .padding(14)
                    .background(.background)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(candidate == template ? Color("BrandOrange") : .clear, lineWidth: 2)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(candidate.title)テンプレート\(candidate.requiresPro ? "、Pro" : "")")
            }
        }
    }

    private var formatSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("画像サイズ", detail: "投稿先に合う比率で書き出します")
            HStack(spacing: 10) {
                ForEach(ShareCardFormat.allCases) { candidate in
                    Button {
                        select(candidate)
                    } label: {
                        VStack(spacing: 6) {
                            HStack(spacing: 4) {
                                Text(candidate.title).font(.subheadline.bold())
                                if candidate.requiresPro && !proAccess.isProUnlocked {
                                    Image(systemName: "lock.fill").font(.caption2)
                                }
                            }
                            Text(candidate.detail).font(.caption2).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(candidate == format ? Color("BrandOrange").opacity(0.12) : Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(candidate == format ? Color("BrandOrange") : .clear, lineWidth: 2)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var paletteSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("配色", detail: "Proでは投稿の雰囲気に合わせて変更できます")
            HStack(spacing: 10) {
                ForEach(ShareCardPalette.allCases) { candidate in
                    Button {
                        select(candidate)
                    } label: {
                        VStack(spacing: 8) {
                            Circle()
                                .fill(candidate.background)
                                .overlay { Circle().stroke(candidate.accent, lineWidth: 4).padding(4) }
                                .frame(width: 38, height: 38)
                            HStack(spacing: 3) {
                                Text(candidate.title).font(.caption.bold())
                                if candidate.requiresPro && !proAccess.isProUnlocked {
                                    Image(systemName: "lock.fill").font(.caption2)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(palette == candidate ? Color("BrandOrange").opacity(0.12) : Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(palette == candidate ? Color("BrandOrange") : .clear, lineWidth: 2)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var textColorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("文字色", detail: "白・黒・オレンジから選べます")
            HStack(spacing: 10) {
                ForEach(ShareCardTextColor.allCases) { candidate in
                    Button {
                        withAnimation(.snappy) { textColor = candidate }
                    } label: {
                        VStack(spacing: 8) {
                            Circle()
                                .fill(candidate.color)
                                .overlay { Circle().stroke(.secondary.opacity(0.45), lineWidth: 1) }
                                .frame(width: 38, height: 38)
                            Text(candidate.title).font(.caption.bold())
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(textColor == candidate ? Color("BrandOrange").opacity(0.12) : Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(textColor == candidate ? Color("BrandOrange") : .clear, lineWidth: 2)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("文字色：\(candidate.title)")
                }
            }
        }
    }

    private var fontSizeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("文字サイズ", detail: "すべての文字をまとめて調整できます")
            HStack(spacing: 12) {
                Button {
                    fontSizeOffset = max(-3, fontSizeOffset - 1)
                } label: {
                    Text("−1")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(fontSizeOffset == -3)

                Text(fontSizeOffset == 0 ? "標準" : "\(fontSizeOffset > 0 ? "+" : "")\(fontSizeOffset)")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 56)

                Button {
                    fontSizeOffset = min(3, fontSizeOffset + 1)
                } label: {
                    Text("+1")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(fontSizeOffset == 3)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("文字サイズ")
        }
    }

    @ViewBuilder
    private var photoSection: some View {
        let recordPhotos = photos.filter { $0.recordID == record.id }
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("写真", detail: template == .collage ? "最大4枚まで選べます" : "先頭の写真を使用します")
            if recordPhotos.isEmpty {
                Label("写真がないため、背景デザインで作成します", systemImage: "photo")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(.background)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(recordPhotos) { photo in
                            if let image = LocalPhotoStore().image(at: photo.thumbnailPath) {
                                let selected = selectedPhotoIDs.contains(photo.id)
                                Button { toggle(photo) } label: {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 96, height: 96)
                                        .clipped()
                                        .overlay(alignment: .topTrailing) {
                                            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                                .font(.title3)
                                                .foregroundStyle(selected ? Color("BrandOrange") : .white)
                                                .background(Circle().fill(.white))
                                                .padding(6)
                                        }
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .stroke(selected ? Color("BrandOrange") : .clear, lineWidth: 3)
                                        }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("写真\(photo.order + 1)を\(selected ? "選択解除" : "選択")")
                            }
                        }
                    }
                }
            }
        }
    }

    private var informationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("表示する情報", detail: "店名は常に表示されます")
            VStack(spacing: 0) {
                if !content.area.isEmpty || !content.category.isEmpty { Toggle("エリア・カテゴリ", isOn: $options.showsArea).padding(14) }
                if content.rating != nil { Divider().padding(.leading, 14); Toggle("評価", isOn: $options.showsRating).padding(14) }
                if content.memo != nil { Divider().padding(.leading, 14); Toggle("メモ", isOn: $options.showsMemo).padding(14) }
                if content.visitDate != nil { Divider().padding(.leading, 14); Toggle("訪問日", isOn: $options.showsVisitDate).padding(14) }
                if !content.tags.isEmpty { Divider().padding(.leading, 14); Toggle("タグ", isOn: $options.showsTags).padding(14) }
            }
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func sectionTitle(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.headline)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func select(_ candidate: ShareCardTemplate) {
        guard !candidate.requiresPro || proAccess.isProUnlocked else {
            presentedSheet = .paywall
            return
        }
        withAnimation(.snappy) { template = candidate }
    }

    private func select(_ candidate: ShareCardFormat) {
        guard !candidate.requiresPro || proAccess.isProUnlocked else {
            presentedSheet = .paywall
            return
        }
        withAnimation(.snappy) { format = candidate }
    }

    private func select(_ candidate: ShareCardPalette) {
        guard !candidate.requiresPro || proAccess.isProUnlocked else {
            presentedSheet = .paywall
            return
        }
        withAnimation(.snappy) { palette = candidate }
    }

    private func toggle(_ photo: RecordPhoto) {
        if let index = selectedPhotoIDs.firstIndex(of: photo.id) {
            selectedPhotoIDs.remove(at: index)
        } else if selectedPhotoIDs.count < 4 {
            selectedPhotoIDs.append(photo.id)
        }
    }

    @MainActor
    private func makeAndShareImage() {
        guard proAccess.isProUnlocked || (!template.requiresPro && !format.requiresPro && !palette.requiresPro) else {
            presentedSheet = .paywall
            return
        }
        let renderer = ImageRenderer(content:
            ShareCardArtwork(
                content: content,
                images: selectedImages,
                template: template,
                format: format,
                palette: palette,
                textColor: textColor,
                fontSizeOffset: fontSizeOffset,
                options: options,
                showsBranding: !proAccess.isProUnlocked
            )
            .frame(width: format.pointSize.width, height: format.pointSize.height)
        )
        renderer.scale = 3
        guard let image = renderer.uiImage else { return }
        presentedSheet = .share(UUID(), image)
    }
}

private struct ShareCardPaywallSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ProPaywallView()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("閉じる") { dismiss() }
                    }
                }
        }
    }
}

private enum ShareCardSheet: Identifiable {
    case paywall
    case share(UUID, UIImage)

    var id: String {
        switch self {
        case .paywall: "paywall"
        case .share(let id, _): id.uuidString
        }
    }
}

private struct ShareCardPreview: View {
    let content: ShareCardContent
    let images: [UIImage]
    let template: ShareCardTemplate
    let format: ShareCardFormat
    let palette: ShareCardPalette
    let textColor: ShareCardTextColor
    let fontSizeOffset: Int
    let options: ShareCardOptions
    let showsBranding: Bool

    var body: some View {
        GeometryReader { proxy in
            let size = format.pointSize
            let scale = min(proxy.size.width / size.width, proxy.size.height / size.height)
            ShareCardArtwork(
                content: content,
                images: images,
                template: template,
                format: format,
                palette: palette,
                textColor: textColor,
                fontSizeOffset: fontSizeOffset,
                options: options,
                showsBranding: showsBranding
            )
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .shadow(color: .black.opacity(0.16), radius: 14, y: 6)
                .scaleEffect(scale)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

struct ShareCardArtwork: View {
    let content: ShareCardContent
    let images: [UIImage]
    let template: ShareCardTemplate
    let format: ShareCardFormat
    let palette: ShareCardPalette
    let textColor: ShareCardTextColor
    let fontSizeOffset: Int
    let options: ShareCardOptions
    let showsBranding: Bool

    var body: some View {
        GeometryReader { proxy in
            switch template {
            case .simple:
                simpleLayout(size: proxy.size)
            case .editorial:
                editorialLayout(size: proxy.size)
            case .collage:
                collageLayout(size: proxy.size)
            case .minimal:
                minimalLayout(size: proxy.size)
            case .typography:
                typographyLayout(size: proxy.size)
            }
        }
        .environment(\.colorScheme, .light)
    }

    @ViewBuilder
    private func simpleLayout(size: CGSize) -> some View {
        if format == .landscape {
            HStack(spacing: 0) {
                photo(images.first).frame(width: size.width * 0.55, height: size.height)
                informationBlock(compact: true)
                    .padding(18)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(palette.background)
                    .foregroundStyle(textColor.color)
            }
        } else {
            VStack(spacing: 0) {
                photo(images.first).frame(height: size.height * 0.57)
                informationBlock(compact: format == .square)
                    .padding(format == .square ? 16 : 22)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(palette.background)
                    .foregroundStyle(textColor.color)
            }
        }
    }

    private func editorialLayout(size: CGSize) -> some View {
        ZStack(alignment: .bottomLeading) {
            photo(images.first)
            LinearGradient(colors: [.clear, .black.opacity(0.88)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: format == .landscape ? 5 : 9) {
                if options.showsArea {
                    Text(metadataLine.uppercased())
                        .font(.system(size: adjustedFontSize(format == .landscape ? 9 : 11), weight: .bold))
                        .tracking(1.8)
                }
                Text(content.placeName)
                    .font(.system(size: adjustedFontSize(format == .landscape ? 27 : 36), weight: .black, design: .serif))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                ratingAndDate
                if options.showsMemo, let memo = content.memo {
                    Text(memo).font(.system(size: adjustedFontSize(format == .landscape ? 10 : 14))).lineLimit(format == .landscape ? 1 : 2)
                }
                tagLine
                brandLine
            }
            .foregroundStyle(textColor.color)
            .padding(format == .landscape ? 18 : 28)
            .frame(maxWidth: format == .landscape ? size.width * 0.7 : .infinity, alignment: .leading)
        }
    }

    private func collageLayout(size: CGSize) -> some View {
        VStack(spacing: 0) {
            photoCollage
                .frame(height: format == .landscape ? size.height : size.height * 0.62)
            if format != .landscape {
                informationBlock(compact: format == .square)
                    .padding(format == .square ? 14 : 20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(palette.ink)
                    .foregroundStyle(textColor.color)
            }
        }
        .overlay(alignment: format == .landscape ? .bottomLeading : .topLeading) {
            if format == .landscape {
                VStack(alignment: .leading, spacing: 4) {
                    Text(content.placeName).font(.system(size: adjustedFontSize(26), weight: .black)).lineLimit(1)
                    ratingAndDate
                    brandLine
                }
                .foregroundStyle(textColor.color)
                .padding(16)
                .background(.black.opacity(0.72))
            }
        }
    }

    @ViewBuilder
    private func minimalLayout(size: CGSize) -> some View {
        if format == .landscape {
            HStack(spacing: 0) {
                minimalInformation(compact: true)
                    .padding(20)
                    .frame(width: size.width * 0.44)
                    .frame(maxHeight: .infinity, alignment: .topLeading)
                photo(images.first)
                    .padding(.vertical, 14)
                    .padding(.trailing, 14)
            }
            .background(palette.background)
            .foregroundStyle(textColor.color)
        } else {
            let isSquare = format == .square
            let inset: CGFloat = isSquare ? 18 : 24
            let headerHeight: CGFloat = isSquare ? 24 : 28
            let photoHeight = size.height * (isSquare ? 0.52 : 0.58)

            VStack(alignment: .leading, spacing: 0) {
                minimalHeader
                    .frame(height: headerHeight, alignment: .topLeading)

                minimalPhoto(images.first, height: photoHeight)

                minimalInformation(compact: true)
                    .padding(.top, isSquare ? 12 : 16)
            }
            .padding(inset)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .background(palette.background)
            .foregroundStyle(textColor.color)
        }
    }

    private var minimalHeader: some View {
        HStack {
            Text("DINING NOTE")
                .font(.system(size: adjustedFontSize(9), weight: .medium, design: .serif))
                .tracking(2.4)
            Spacer()
            if options.showsArea {
                Text(metadataLine)
                    .font(.system(size: adjustedFontSize(8), design: .monospaced))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(textColor.color)
    }

    private func minimalInformation(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 5 : 8) {
            if format == .landscape, options.showsArea, !metadataLine.isEmpty {
                Text(metadataLine.uppercased())
                    .font(.system(size: adjustedFontSize(7), design: .monospaced))
                    .tracking(1.1)
                    .foregroundStyle(textColor.color)
            }
            Text(content.placeName)
                .font(.system(size: adjustedFontSize(compact ? 22 : 29), weight: .medium, design: .serif))
                .lineLimit(2)
                .minimumScaleFactor(0.65)
            Rectangle()
                .fill(palette.accent)
                .frame(width: compact ? 28 : 40, height: 1)
            ratingAndDate
            if options.showsMemo, let memo = content.memo {
                Text(memo)
                    .font(.system(size: adjustedFontSize(compact ? 8 : 11), weight: .light, design: .serif))
                    .lineLimit(compact ? 2 : 3)
                    .foregroundStyle(textColor.color.opacity(0.72))
            }
            tagLine
            if format == .landscape {
                Spacer(minLength: 0)
            }
            brandLine
        }
    }

    @ViewBuilder
    private func typographyLayout(size: CGSize) -> some View {
        if format == .landscape {
            HStack(spacing: 0) {
                typographyInformation(compact: true)
                    .padding(18)
                    .frame(width: size.width * 0.48)
                    .frame(maxHeight: .infinity, alignment: .topLeading)
                    .background(palette.ink)
                photo(images.first)
            }
        } else {
            VStack(spacing: 0) {
                photo(images.first)
                    .frame(height: size.height * (format == .square ? 0.52 : 0.58))
                typographyInformation(compact: format == .square)
                    .padding(format == .square ? 14 : 20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(palette.ink)
            }
        }
    }

    private func typographyInformation(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 7) {
            HStack {
                Text("EAT / NOTE")
                    .font(.system(size: adjustedFontSize(compact ? 7 : 9), weight: .black, design: .monospaced))
                    .tracking(1.5)
                Spacer()
                if options.showsRating, let rating = content.rating {
                    Text("★\(rating)")
                        .font(.system(size: adjustedFontSize(compact ? 9 : 11), weight: .bold, design: .monospaced))
                        .foregroundStyle(textColor.color)
                }
            }
            Text(content.placeName)
                .font(.system(size: adjustedFontSize(compact ? 25 : 34), weight: .black, design: .rounded))
                .lineLimit(2)
                .minimumScaleFactor(0.58)
            HStack(spacing: 7) {
                if options.showsArea, !metadataLine.isEmpty {
                    Text(metadataLine.uppercased())
                }
                if options.showsVisitDate, let visitDate = content.visitDate {
                    Text(visitDate)
                }
            }
            .font(.system(size: adjustedFontSize(compact ? 7 : 9), weight: .bold, design: .monospaced))
            .lineLimit(1)
            if options.showsMemo, let memo = content.memo {
                Text(memo)
                    .font(.system(size: adjustedFontSize(compact ? 8 : 10), weight: .medium, design: .monospaced))
                    .lineLimit(compact ? 1 : 2)
                    .opacity(0.76)
            }
            tagLine
            Spacer(minLength: 0)
            brandLine
        }
        .foregroundStyle(textColor.color)
    }

    private var photoCollage: some View {
        GeometryReader { proxy in
            let gap: CGFloat = 3
            if images.count <= 1 {
                photo(images.first)
            } else {
                HStack(spacing: gap) {
                    photo(images.first)
                        .frame(width: proxy.size.width * 0.62)
                    VStack(spacing: gap) {
                        ForEach(Array(images.dropFirst().prefix(3).enumerated()), id: \.offset) { _, image in
                            photo(image)
                        }
                    }
                }
            }
        }
    }

    private func informationBlock(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 5 : 8) {
            if options.showsArea, !metadataLine.isEmpty {
                Text(metadataLine.uppercased())
                    .font(.system(size: adjustedFontSize(compact ? 8 : 10), weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(palette.accent)
            }
            Text(content.placeName)
                .font(.system(size: adjustedFontSize(compact ? 24 : 31), weight: .black, design: .rounded))
                .lineLimit(2)
                .minimumScaleFactor(0.65)
            ratingAndDate
            if options.showsMemo, let memo = content.memo {
                Text(memo)
                    .font(.system(size: adjustedFontSize(compact ? 10 : 13)))
                    .lineLimit(compact ? 1 : 2)
                    .foregroundStyle(textColor.color.opacity(0.72))
            }
            tagLine
            Spacer(minLength: 0)
            brandLine
        }
    }

    private var ratingAndDate: some View {
        HStack(spacing: 8) {
            if options.showsRating, let rating = content.rating {
                Text("★ \(rating)").fontWeight(.bold)
            }
            if options.showsVisitDate, let visitDate = content.visitDate {
                Text(visitDate)
            }
        }
        .font(.system(size: adjustedFontSize(format == .landscape ? 9 : 11)))
    }

    @ViewBuilder
    private var tagLine: some View {
        if options.showsTags, !content.tags.isEmpty {
            Text(content.tags.prefix(4).map { "#\($0.replacingOccurrences(of: " ", with: ""))" }.joined(separator: "  "))
                .font(.system(size: adjustedFontSize(format == .landscape ? 8 : 10), weight: .semibold))
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var brandLine: some View {
        if showsBranding {
            HStack(spacing: 4) {
                Image(systemName: "fork.knife")
                Text("GOURMEPP").fontWeight(.bold).tracking(1.2)
            }
            .font(.system(size: adjustedFontSize(format == .landscape ? 7 : 9)))
            .opacity(0.72)
        }
    }

    private var metadataLine: String {
        [content.area, content.category].filter { !$0.isEmpty }.joined(separator: "  •  ")
    }

    private func adjustedFontSize(_ size: CGFloat) -> CGFloat {
        max(6, size + CGFloat(fontSizeOffset))
    }

    @ViewBuilder
    private func minimalPhoto(_ image: UIImage?, height: CGFloat) -> some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: [palette.background, palette.accent],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "fork.knife.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.white.opacity(0.82))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipped()
    }

    private func photo(_ image: UIImage?) -> some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    LinearGradient(
                        colors: [palette.background, palette.accent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: "fork.knife.circle.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(.white.opacity(0.82))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
