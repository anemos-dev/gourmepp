import MapKit
import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct PlaceEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppErrorCenter.self) private var errors
    let place: Place
    @State private var name: String
    @State private var address: String
    @State private var phoneNumber: String
    @State private var websiteURL: String
    @State private var category: String
    @State private var openingHours: String
    @State private var latitude: Double
    @State private var longitude: Double
    @State private var isLocating = false

    init(place: Place) {
        self.place = place
        _name = State(initialValue: place.name)
        _address = State(initialValue: place.address)
        _phoneNumber = State(initialValue: place.phoneNumber)
        _websiteURL = State(initialValue: place.websiteURL)
        _category = State(initialValue: place.category)
        _openingHours = State(initialValue: place.openingHours)
        _latitude = State(initialValue: place.latitude)
        _longitude = State(initialValue: place.longitude)
    }

    var body: some View {
        Form {
            Section("基本情報") {
                TextField("店名", text: $name)
                TextField("住所", text: $address, axis: .vertical)
                TextField("カテゴリ", text: $category)
                TextField("電話番号", text: $phoneNumber)
                    .keyboardType(.phonePad)
                TextField("Webサイト", text: $websiteURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                TextField("営業時間", text: $openingHours, axis: .vertical)
            }
            Section("地図上の位置") {
                if latitude != 0 || longitude != 0 {
                    Map(initialPosition: .region(region)) {
                        Marker(name.isEmpty ? "店舗" : name, coordinate: coordinate)
                    }
                    .frame(height: 190)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    LabeledContent("緯度", value: latitude.formatted(.number.precision(.fractionLength(6))))
                    LabeledContent("経度", value: longitude.formatted(.number.precision(.fractionLength(6))))
                } else {
                    ContentUnavailableView("位置が未設定です", systemImage: "mappin.slash", description: Text("住所から位置を検索できます。"))
                }
                Button {
                    Task { await locateFromAddress() }
                } label: {
                    if isLocating {
                        ProgressView()
                    } else {
                        Label("店名と住所から位置を検索", systemImage: "mappin.and.ellipse")
                    }
                }
                .disabled(isLocating || (name.isEmpty && address.isEmpty))
            }
            Section("重複の整理") {
                NavigationLink {
                    DuplicatePlaceMergeView(place: place)
                } label: {
                    Label("重複店舗を統合", systemImage: "arrow.triangle.merge")
                }
                Text("同じ店舗を複数登録した場合、記録をひとつの店舗へまとめられます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("店舗情報を編集")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存", action: save)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    private var region: MKCoordinateRegion {
        MKCoordinateRegion(center: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.015, longitudeDelta: 0.015))
    }

    private func locateFromAddress() async {
        isLocating = true
        defer { isLocating = false }
        do {
            let candidates = try await AppleMapSearchClient().search(query: "\(name) \(address)", region: nil)
            guard let candidate = candidates.first else {
                errors.show("候補が見つかりませんでした。住所を詳しく入力してください。", title: "位置を設定できませんでした")
                return
            }
            latitude = candidate.latitude
            longitude = candidate.longitude
            if address.isEmpty { address = candidate.address }
        } catch {
            errors.show(error, title: "位置を検索できませんでした")
        }
    }

    private func save() {
        place.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        place.address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        place.area = Place.area(from: place.address)
        place.phoneNumber = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        place.websiteURL = normalizedWebsite(websiteURL)
        place.category = category.trimmingCharacters(in: .whitespacesAndNewlines)
        place.openingHours = openingHours.trimmingCharacters(in: .whitespacesAndNewlines)
        place.latitude = latitude
        place.longitude = longitude
        do {
            try context.save()
            dismiss()
        } catch {
            errors.show(error, title: "店舗情報を保存できませんでした")
        }
    }

    private func normalizedWebsite(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if URL(string: trimmed)?.scheme != nil { return trimmed }
        return "https://\(trimmed)"
    }
}

struct DuplicatePlaceMergeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppErrorCenter.self) private var errors
    let place: Place
    @Query private var places: [Place]
    @Query private var records: [RestaurantRecord]
    @State private var target: Place?

    private var candidates: [Place] {
        places.filter { $0.id != place.id }.sorted {
            similarity($0) > similarity($1)
        }
    }

    var body: some View {
        Group {
            if candidates.isEmpty {
                ContentUnavailableView("ほかの店舗がありません", systemImage: "building.2", description: Text("統合できる店舗はありません。"))
            } else {
                List(candidates) { candidate in
                    Button {
                        target = candidate
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(candidate.name)
                                .foregroundStyle(.primary)
                            Text(candidate.address)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("統合先を選ぶ")
        .alert("「\(place.name)」へ統合しますか？", isPresented: Binding(
            get: { target != nil },
            set: { if !$0 { target = nil } }
        )) {
            Button("統合", role: .destructive) {
                if let target { merge(target) }
            }
            Button("キャンセル", role: .cancel) { target = nil }
        } message: {
            if let target {
                Text("「\(target.name)」に紐づく記録をこの店舗へ移動し、重複店舗を削除します。")
            }
        }
    }

    private func similarity(_ candidate: Place) -> Int {
        var score = 0
        if candidate.name.localizedCaseInsensitiveContains(place.name) || place.name.localizedCaseInsensitiveContains(candidate.name) { score += 2 }
        if !place.area.isEmpty && candidate.area == place.area { score += 1 }
        return score
    }

    private func merge(_ duplicate: Place) {
        records.filter { $0.placeID == duplicate.id }.forEach {
            $0.placeID = place.id
            $0.updatedAt = .now
        }
        context.delete(duplicate)
        do {
            try context.save()
            target = nil
            dismiss()
        } catch {
            errors.show(error, title: "店舗を統合できませんでした")
        }
    }
}

struct PhotoGalleryView: View {
    let photos: [RecordPhoto]
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                Group {
                    if let image = LocalPhotoStore().image(at: photo.imagePath) {
                        ZoomableImage(image: image)
                            .accessibilityLabel("写真 \(index + 1)")
                    } else {
                        ContentUnavailableView("写真を読み込めません", systemImage: "photo.badge.exclamationmark")
                    }
                }
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        .background(.black)
        .navigationTitle("\(selection + 1) / \(photos.count)")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ZoomableImage: View {
    let image: UIImage
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .scaleEffect(scale)
            .gesture(
                MagnifyGesture()
                    .onChanged { value in scale = min(max(lastScale * value.magnification, 1), 5) }
                    .onEnded { _ in lastScale = scale }
            )
            .onTapGesture(count: 2) {
                withAnimation {
                    scale = scale > 1 ? 1 : 2
                    lastScale = scale
                }
            }
    }
}

struct ReleasePhotoManagementView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppErrorCenter.self) private var errors
    let recordID: UUID
    @Query private var allPhotos: [RecordPhoto]
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var showCamera = false
    @State private var cameraImage: UIImage?
    @State private var isSaving = false

    private var photos: [RecordPhoto] {
        allPhotos.filter { $0.recordID == recordID }.sorted { $0.order < $1.order }
    }

    var body: some View {
        List {
            Section {
                PhotosPicker(selection: $selectedItems, maxSelectionCount: nil, matching: .images) {
                    Label("ライブラリから追加", systemImage: "photo.on.rectangle")
                }
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button {
                        showCamera = true
                    } label: {
                        Label("写真を撮る", systemImage: "camera")
                    }
                }
                if isSaving { ProgressView("写真を保存中…") }
            }
            Section("写真") {
                if photos.isEmpty {
                    ContentUnavailableView("写真はまだありません", systemImage: "photo", description: Text("ライブラリまたはカメラから追加できます。"))
                } else {
                    ForEach(photos) { photo in
                        NavigationLink {
                            PhotoGalleryView(photos: photos)
                        } label: {
                            HStack {
                                if let image = LocalPhotoStore().image(at: photo.thumbnailPath) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 72, height: 72)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                Text("写真 \(photo.order + 1)")
                                Spacer()
                                Image(systemName: "line.3.horizontal")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onMove(perform: move)
                    .onDelete(perform: remove)
                }
            }
        }
        .navigationTitle("写真を管理")
        .disabled(isSaving)
        .toolbar { EditButton() }
        .sheet(isPresented: $showCamera) {
            CameraPicker(image: $cameraImage)
                .ignoresSafeArea()
        }
        .onChange(of: selectedItems) { _, newValue in
            guard !newValue.isEmpty else { return }
            Task { await saveSelectedItems(newValue) }
        }
        .onChange(of: cameraImage) { _, image in
            guard let image, let data = image.jpegData(compressionQuality: 0.92) else { return }
            save(data: data)
            cameraImage = nil
        }
    }

    private func saveSelectedItems(_ items: [PhotosPickerItem]) async {
        isSaving = true
        defer { isSaving = false }
        var failed = 0
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                failed += 1
                continue
            }
            if !save(data: data) { failed += 1 }
        }
        selectedItems = []
        if failed > 0 {
            errors.show("\(failed)枚の写真を保存できませんでした。空き容量を確認して、もう一度お試しください。", title: "一部の写真を保存できませんでした")
        }
    }

    @discardableResult
    private func save(data: Data) -> Bool {
        do {
            let order = (photos.map(\.order).max() ?? -1) + 1
            let saved = try LocalPhotoStore().save(data, recordID: recordID, order: order)
            context.insert(RecordPhoto(recordID: recordID, imagePath: saved.imagePath, thumbnailPath: saved.thumbnailPath, order: order))
            try context.save()
            return true
        } catch {
            errors.show(error, title: "写真を保存できませんでした")
            return false
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var ordered = photos
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, photo) in ordered.enumerated() { photo.order = index }
        do { try context.save() } catch { errors.show(error, title: "並び順を保存できませんでした") }
    }

    private func remove(at offsets: IndexSet) {
        for index in offsets {
            LocalPhotoStore().delete(photo: photos[index])
            context.delete(photos[index])
        }
        do { try context.save() } catch { errors.show(error, title: "写真を削除できませんでした") }
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    @Binding var image: UIImage?

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.delegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraPicker
        init(parent: CameraPicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.image = info[.originalImage] as? UIImage
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
