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
    @State private var selected: RestaurantRecord?
    @State private var filter: RecordStatus? = nil
    @State private var locationService = DeviceLocationService()
    @State private var proMode: ProMapMode = .pins

    private var filteredRecords: [RestaurantRecord] {
        records.filter { !$0.isDeleted && (filter == nil || $0.status == filter) }
    }
    private var nearbyWishlistRecords: [RestaurantRecord] {
        guard let location = locationService.currentLocation else { return [] }
        return records.filter { record in
            guard !record.isDeleted,
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
                selected: $selected,
                focusCoordinate: locationService.currentLocation?.coordinate,
                showsDensity: proAccess.isProUnlocked && proMode == .density,
                densityColor: UIColor(proPreferences.accentColor)
            )
            .overlay(alignment: .bottom) {
                if let selected, let place = places.first(where: { $0.id == selected.placeID }) {
                    NavigationLink { PlaceDetailView(recordID: selected.id) } label: {
                        RecordCard(record: selected, place: place, compact: false, photo: photos.first { $0.recordID == selected.id })
                            .padding()
                            .background(.regularMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .padding()
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
            selected = nil
            if newMode == .nearbyWishlist { locationService.request() }
        }
    }

    private func distance(to record: RestaurantRecord, from location: CLLocation) -> CLLocationDistance {
        guard let place = places.first(where: { $0.id == record.placeID }) else { return .greatestFiniteMagnitude }
        return location.distance(from: CLLocation(latitude: place.latitude, longitude: place.longitude))
    }
}

struct RecordsMap: UIViewRepresentable {
    let records: [RestaurantRecord]; let places: [Place]; @Binding var selected: RestaurantRecord?; var focusCoordinate: CLLocationCoordinate2D? = nil; var showsDensity = false; var densityColor = UIColor(red: 0.835, green: 0.4, blue: 0, alpha: 1)
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> MKMapView { let map = MKMapView(); map.delegate = context.coordinator; map.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: "place"); map.showsUserLocation = true; return map }
    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.parent = self
        map.removeAnnotations(map.annotations.filter { !($0 is MKUserLocation) })
        map.removeOverlays(map.overlays)
        let annotations = records.compactMap { record -> RecordAnnotation? in
            guard let place = places.first(where: { $0.id == record.placeID }), place.latitude != 0 || place.longitude != 0 else { return nil }
            return RecordAnnotation(record: record, place: place)
        }
        if showsDensity {
            let circles = annotations.map { MKCircle(center: $0.coordinate, radius: 1_200) }
            map.addOverlays(circles)
        } else {
            map.addAnnotations(annotations)
        }
        if let focusCoordinate, context.coordinator.shouldFocus(on: focusCoordinate) {
            map.setRegion(MKCoordinateRegion(center: focusCoordinate, latitudinalMeters: 2_000, longitudinalMeters: 2_000), animated: true)
        } else if !annotations.isEmpty && !context.coordinator.didSetRegion {
            map.showAnnotations(annotations, animated: false)
            context.coordinator.didSetRegion = true
        }
    }
    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: RecordsMap
        var didSetRegion = false
        var lastFocus: CLLocationCoordinate2D?
        init(_ parent: RecordsMap) { self.parent = parent }
        func shouldFocus(on coordinate: CLLocationCoordinate2D) -> Bool {
            defer { lastFocus = coordinate }
            guard let lastFocus else { return true }
            return abs(lastFocus.latitude - coordinate.latitude) > 0.00001 || abs(lastFocus.longitude - coordinate.longitude) > 0.00001
        }
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? { guard let annotation = annotation as? RecordAnnotation else { return nil }; let view = mapView.dequeueReusableAnnotationView(withIdentifier: "place", for: annotation) as! MKMarkerAnnotationView; view.canShowCallout = false; view.clusteringIdentifier = "records"; view.markerTintColor = annotation.record.isFavorite ? .systemYellow : UIColor(red: 0.835, green: 0.4, blue: 0, alpha: 1); view.glyphImage = UIImage(systemName: annotation.record.status == .visited ? "checkmark" : "bookmark.fill"); return view }
        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) { if let annotation = view.annotation as? RecordAnnotation { parent.selected = annotation.record } }
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let circle = overlay as? MKCircle else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKCircleRenderer(circle: circle)
            renderer.fillColor = parent.densityColor.withAlphaComponent(0.22)
            renderer.strokeColor = parent.densityColor.withAlphaComponent(0.42)
            renderer.lineWidth = 1
            return renderer
        }
    }
}
final class RecordAnnotation: NSObject, MKAnnotation { let record: RestaurantRecord; let coordinate: CLLocationCoordinate2D; let title: String?; init(record: RestaurantRecord, place: Place) { self.record = record; coordinate = CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude); title = place.name } }
