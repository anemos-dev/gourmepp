import SwiftUI
import SwiftData
import MapKit

enum ProMapMode: String, CaseIterable, Identifiable {
    case pins, density, nearbyWishlist
    var id: String { rawValue }
    var title: String {
        switch self {
        case .pins: "ピン"
        case .density: "訪問密度"
        case .nearbyWishlist: "近くの行きたい"
        }
    }
}

struct MapScreen: View {
    @Environment(ProAccessController.self) private var proAccess
    @Environment(ProPreferences.self) private var proPreferences
    @Query private var records: [RestaurantRecord]
    @Query private var places: [Place]
    @Query private var photos: [RecordPhoto]
    @State private var selectedRecordIDs: [UUID] = []
    @State private var filter: RecordStatus? = nil
    @State private var locationService = DeviceLocationService()
    @State private var proMode: ProMapMode = .pins

    private var filteredRecords: [RestaurantRecord] {
        records.filter { !$0.isTrashed && (filter == nil || $0.status == filter) }
    }
    private var nearbyWishlistRecords: [RestaurantRecord] {
        guard let location = locationService.currentLocation else { return [] }
        return records.filter { record in
            guard !record.isTrashed,
                  record.status == .wantToGo,
                  let place = places.first(where: { $0.id == record.placeID }),
                  place.latitude != 0 || place.longitude != 0
            else { return false }
            let destination = CLLocation(latitude: place.latitude, longitude: place.longitude)
            return location.distance(from: destination) <= 5_000
        }
        .sorted { distance(to: $0, from: location) < distance(to: $1, from: location) }
    }
    private var displayedRecords: [RestaurantRecord] {
        guard proAccess.isProUnlocked else { return filteredRecords }
        switch proMode {
        case .pins: return filteredRecords
        case .density: return filteredRecords.filter { $0.status == .visited }
        case .nearbyWishlist: return nearbyWishlistRecords.filter { filter == nil || $0.status == filter }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            RecordsMap(
                records: displayedRecords,
                places: places,
                selectedRecordIDs: $selectedRecordIDs,
                focusCoordinate: locationService.currentLocation?.coordinate,
                showsDensity: proAccess.isProUnlocked && proMode == .density,
                densityColor: UIColor(proPreferences.accentColor)
            )
            .overlay(alignment: .topLeading) {
                if proAccess.isProUnlocked && proMode == .density {
                    DensityLegend(color: proPreferences.accentColor)
                        .padding(12)
                }
            }
            .overlay(alignment: .bottom) {
                if !selectedRecords.isEmpty {
                    VStack(alignment: .trailing, spacing: 4) {
                        Button {
                            selectedRecordIDs = []
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption.bold())
                                .frame(width: 30, height: 30)
                                .background(.regularMaterial, in: Circle())
                        }
                        .accessibilityLabel("地図の選択を閉じる")
                        .padding(.trailing, 16)

                        ScrollView(.horizontal, showsIndicators: selectedRecords.count > 1) {
                            HStack(spacing: 10) {
                                ForEach(selectedRecords) { record in
                                    NavigationLink { PlaceDetailView(recordID: record.id) } label: {
                                        MapSelectionCard(
                                            record: record,
                                            place: places.first { $0.id == record.placeID },
                                            photo: photos.first { $0.recordID == record.id }
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                    .padding(.bottom, 12)
                } else if proAccess.isProUnlocked && proMode == .nearbyWishlist && locationService.currentLocation == nil {
                    Button {
                        locationService.request()
                    } label: {
                        Label("現在地から近いお店を探す", systemImage: "location.fill")
                            .padding(.horizontal, 18)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(proPreferences.accentColor)
                    .padding(.bottom, 24)
                } else if proAccess.isProUnlocked && proMode == .nearbyWishlist && nearbyWishlistRecords.isEmpty {
                    ContentUnavailableView(
                        "近くに行きたいお店がありません",
                        systemImage: "mappin.slash",
                        description: Text("現在地から5km以内の記録が対象です。")
                    )
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                    .padding()
                }
            }
        }
        .navigationTitle("マップ")
        .navigationBarTitleDisplayMode(.inline)
        .themeScreenBackground()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Section("状態") {
                        Picker("状態", selection: $filter) {
                            Text("すべて").tag(RecordStatus?.none)
                            ForEach(RecordStatus.allCases) { Text($0.title).tag(Optional($0)) }
                        }
                    }
                    if proAccess.isProUnlocked {
                        Section("表示") {
                            Picker("地図の表示", selection: $proMode) {
                                ForEach(ProMapMode.allCases) { Text($0.title).tag($0) }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel("地図を絞り込む")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { locationService.request() } label: {
                    Image(systemName: locationService.currentLocation == nil ? "location" : "location.fill")
                }
                .accessibilityLabel("現在地へ戻る")
            }
        }
        .onChange(of: proMode) { _, newMode in
            selectedRecordIDs = []
            if newMode == .nearbyWishlist { locationService.request() }
        }
    }

    private func distance(to record: RestaurantRecord, from location: CLLocation) -> CLLocationDistance {
        guard let place = places.first(where: { $0.id == record.placeID }) else { return .greatestFiniteMagnitude }
        return location.distance(from: CLLocation(latitude: place.latitude, longitude: place.longitude))
    }

    private var selectedRecords: [RestaurantRecord] {
        selectedRecordIDs.compactMap { id in displayedRecords.first { $0.id == id } }
    }
}

private struct DensityLegend: View {
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("訪問密度", systemImage: "hexagon.fill")
                .font(.caption.bold())
            HStack(spacing: 8) {
                Text("少")
                Capsule()
                    .fill(LinearGradient(colors: [color.opacity(0.2), color], startPoint: .leading, endPoint: .trailing))
                    .frame(width: 72, height: 7)
                Text("多")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("訪問密度。六角形の色が濃いほど、そのエリアの訪問店舗数が多くなります。凡例は少から多です。")
    }
}

private struct MapSelectionCard: View {
    let record: RestaurantRecord
    let place: Place?
    let photo: RecordPhoto?

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let photo, let image = LocalPhotoStore().image(at: photo.thumbnailPath) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Color("BrandOrange").opacity(0.25)
                        .overlay { Image(systemName: "fork.knife").foregroundStyle(Color("BrandOrange")) }
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(place?.name ?? "店舗").font(.subheadline.bold()).lineLimit(2)
                Text(record.status.title).font(.caption).foregroundStyle(.secondary)
                if record.displayRating > 0 {
                    Text("★ \(record.ratingText)").font(.caption).foregroundStyle(Color("BrandOrange"))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(width: 250, height: 84)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityLabel("\(place?.name ?? "店舗")の詳細を開く")
    }
}

struct RecordsMap: UIViewRepresentable {
    let records: [RestaurantRecord]; let places: [Place]; @Binding var selectedRecordIDs: [UUID]; var focusCoordinate: CLLocationCoordinate2D? = nil; var showsDensity = false; var densityColor = UIColor(red: 0.835, green: 0.4, blue: 0, alpha: 1)
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> MKMapView { let map = MKMapView(); map.delegate = context.coordinator; map.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: "place"); map.showsUserLocation = true; return map }
    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.parent = self
        let annotations = records.compactMap { record -> RecordAnnotation? in
            guard let place = places.first(where: { $0.id == record.placeID }), place.latitude != 0 || place.longitude != 0 else { return nil }
            return RecordAnnotation(record: record, place: place)
        }
        let signature = annotations.map {
            "\($0.record.id):\($0.coordinate.latitude):\($0.coordinate.longitude):\($0.record.status):\($0.record.isFavorite)"
        }
        context.coordinator.densityAnnotations = annotations
        let densityColorChanged = showsDensity && context.coordinator.lastDensityColor?.isEqual(densityColor) != true
        if context.coordinator.annotationSignature != signature || context.coordinator.lastShowsDensity != showsDensity || densityColorChanged {
            context.coordinator.annotationSignature = signature
            context.coordinator.lastShowsDensity = showsDensity
            context.coordinator.lastDensityColor = densityColor
            map.removeAnnotations(map.annotations.filter { !($0 is MKUserLocation) })
            map.removeOverlays(map.overlays)
            context.coordinator.densityRecordCounts.removeAll()
            if showsDensity {
                context.coordinator.densityZoomTier = densityZoomTier(for: map)
                addDensityOverlays(to: map, annotations: annotations, tier: context.coordinator.densityZoomTier)
            } else {
                context.coordinator.densityZoomTier = nil
                map.addAnnotations(annotations)
            }
        }
        if selectedRecordIDs.isEmpty {
            for annotation in map.selectedAnnotations {
                map.deselectAnnotation(annotation, animated: false)
            }
        }
        if let focusCoordinate, context.coordinator.shouldFocus(on: focusCoordinate) {
            map.setRegion(MKCoordinateRegion(center: focusCoordinate, latitudinalMeters: 2_000, longitudinalMeters: 2_000), animated: true)
        } else if !annotations.isEmpty && !context.coordinator.didSetRegion {
            map.showAnnotations(annotations, animated: false)
            context.coordinator.didSetRegion = true
        }
    }

    private func addDensityOverlays(to map: MKMapView, annotations: [RecordAnnotation], tier: DensityZoomTier?) {
        guard let tier else { return }
        let hexagons = makeDensityHexagons(from: annotations, radiusMeters: tier.radiusMeters)
        map.delegate.flatMap { $0 as? Coordinator }?.densityRecordCounts = Dictionary(
            uniqueKeysWithValues: hexagons.map { (ObjectIdentifier($0.polygon), $0.recordCount) }
        )
        map.addOverlays(hexagons.map(\.polygon))
    }

    private func densityZoomTier(for map: MKMapView) -> DensityZoomTier {
        let latitude = map.region.center.latitude
        let visibleWidthMeters = map.visibleMapRect.width * MKMetersPerMapPointAtLatitude(latitude)
        return DensityZoomTier.forVisibleWidth(visibleWidthMeters)
    }

    private func makeDensityHexagons(from annotations: [RecordAnnotation], radiusMeters: Double) -> [DensityHexagon] {
        guard !annotations.isEmpty else { return [] }

        let referenceLatitude = annotations.map(\.coordinate.latitude).reduce(0, +) / Double(annotations.count)
        let metersPerMapPoint = MKMetersPerMapPointAtLatitude(referenceLatitude)
        let radius = radiusMeters / metersPerMapPoint
        let origin = MKMapPoint(annotations[0].coordinate)
        var grouped: [HexCell: [RecordAnnotation]] = [:]

        for annotation in annotations {
            let point = MKMapPoint(annotation.coordinate)
            let x = (point.x - origin.x) / radius
            let y = (point.y - origin.y) / radius
            let q = sqrt(3) / 3 * x - y / 3
            let r = 2 / 3 * y
            grouped[HexCell.rounded(q: q, r: r), default: []].append(annotation)
        }

        return grouped.map { cell, members in
            let centerX = origin.x + radius * sqrt(3) * (Double(cell.q) + Double(cell.r) / 2)
            let centerY = origin.y + radius * 1.5 * Double(cell.r)
            let center = MKMapPoint(x: centerX, y: centerY)
            let vertices = (0..<6).map { index -> CLLocationCoordinate2D in
                let angle = (Double(index) * 60 + 30) * .pi / 180
                let point = MKMapPoint(x: center.x + radius * 0.9 * cos(angle), y: center.y + radius * 0.9 * sin(angle))
                return point.coordinate
            }
            return DensityHexagon(
                polygon: MKPolygon(coordinates: vertices, count: vertices.count),
                recordCount: members.count
            )
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: RecordsMap
        var didSetRegion = false
        var lastFocus: CLLocationCoordinate2D?
        var annotationSignature: [String] = []
        var lastShowsDensity: Bool?
        var lastDensityColor: UIColor?
        var densityRecordCounts: [ObjectIdentifier: Int] = [:]
        var densityAnnotations: [RecordAnnotation] = []
        fileprivate var densityZoomTier: DensityZoomTier?
        init(_ parent: RecordsMap) { self.parent = parent }
        func shouldFocus(on coordinate: CLLocationCoordinate2D) -> Bool {
            defer { lastFocus = coordinate }
            guard let lastFocus else { return true }
            return abs(lastFocus.latitude - coordinate.latitude) > 0.00001 || abs(lastFocus.longitude - coordinate.longitude) > 0.00001
        }
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? { guard let annotation = annotation as? RecordAnnotation else { return nil }; let view = mapView.dequeueReusableAnnotationView(withIdentifier: "place", for: annotation) as! MKMarkerAnnotationView; view.canShowCallout = false; view.clusteringIdentifier = "records"; view.markerTintColor = annotation.record.isFavorite ? .systemYellow : UIColor(red: 0.835, green: 0.4, blue: 0, alpha: 1); view.glyphImage = UIImage(systemName: annotation.record.status == .visited ? "checkmark" : "bookmark.fill"); return view }
        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if let cluster = view.annotation as? MKClusterAnnotation {
                parent.selectedRecordIDs = cluster.memberAnnotations.compactMap { ($0 as? RecordAnnotation)?.record.id }
            } else if let annotation = view.annotation as? RecordAnnotation {
                parent.selectedRecordIDs = [annotation.record.id]
            }
        }
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polygon = overlay as? MKPolygon,
                  let recordCount = densityRecordCounts[ObjectIdentifier(polygon)] else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let renderer = MKPolygonRenderer(polygon: polygon)
            let intensity = min(log2(Double(recordCount)) / 3, 1)
            renderer.fillColor = parent.densityColor.withAlphaComponent(0.18 + 0.5 * intensity)
            renderer.strokeColor = parent.densityColor.withAlphaComponent(0.35 + 0.5 * intensity)
            renderer.lineWidth = 1.2
            return renderer
        }
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            guard parent.showsDensity else { return }
            let tier = parent.densityZoomTier(for: mapView)
            guard tier != densityZoomTier else { return }
            mapView.removeOverlays(mapView.overlays)
            densityRecordCounts.removeAll()
            densityZoomTier = tier
            parent.addDensityOverlays(to: mapView, annotations: densityAnnotations, tier: tier)
        }
    }
}

private struct HexCell: Hashable {
    let q: Int
    let r: Int

    static func rounded(q: Double, r: Double) -> HexCell {
        let s = -q - r
        var roundedQ = q.rounded()
        var roundedR = r.rounded()
        let roundedS = s.rounded()

        if abs(roundedQ - q) > abs(roundedR - r), abs(roundedQ - q) > abs(roundedS - s) {
            roundedQ = -roundedR - roundedS
        } else if abs(roundedR - r) > abs(roundedS - s) {
            roundedR = -roundedQ - roundedS
        }
        return HexCell(q: Int(roundedQ), r: Int(roundedR))
    }
}

private struct DensityHexagon {
    let polygon: MKPolygon
    let recordCount: Int
}

private struct DensityZoomTier: Equatable {
    let radiusMeters: Double

    static func forVisibleWidth(_ meters: Double) -> DensityZoomTier {
        // 表示幅の約1割を目安に、街区から全国表示まで段階的に集約する。
        let targetRadius = meters / 10
        let radii: [Double] = [
            25, 50, 100, 200, 500,
            1_000, 2_000, 5_000, 10_000, 20_000, 50_000,
            100_000, 200_000, 500_000, 1_000_000, 2_000_000, 5_000_000
        ]
        let tierRadius = radii.first { $0 >= targetRadius } ?? 5_000_000
        return DensityZoomTier(radiusMeters: tierRadius * 0.8)
    }
}

final class RecordAnnotation: NSObject, MKAnnotation { let record: RestaurantRecord; let coordinate: CLLocationCoordinate2D; let title: String?; init(record: RestaurantRecord, place: Place) { self.record = record; coordinate = CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude); title = place.name } }
