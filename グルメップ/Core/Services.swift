import Foundation
import MapKit
import CoreLocation
import UIKit
import Observation

protocol PhotoStore { func save(_ data: Data, recordID: UUID, order: Int) throws -> (imagePath: String, thumbnailPath: String); func image(at path: String) -> UIImage?; func delete(recordID: UUID) }
final class LocalPhotoStore: PhotoStore {
    private let fm = FileManager.default
    private var root: URL { let url = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("RecordPhotos", isDirectory: true); try? fm.createDirectory(at: url, withIntermediateDirectories: true); return url }
    func save(_ data: Data, recordID: UUID, order: Int) throws -> (imagePath: String, thumbnailPath: String) {
        let folder = root.appendingPathComponent(recordID.uuidString, isDirectory: true); try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let imageName = "\(order)-\(UUID().uuidString).jpg"; let imageURL = folder.appendingPathComponent(imageName); try data.write(to: imageURL, options: .atomic)
        let thumbName = "thumb-\(imageName)"; let thumbURL = folder.appendingPathComponent(thumbName)
        guard let source = UIImage(data: data) else { throw CocoaError(.fileReadCorruptFile) }
        let normalized = source.preparingForDisplay() ?? source
        let quality = PhotoQuality(rawValue: UserDefaults.standard.string(forKey: "photoQuality") ?? "standard") ?? .standard
        guard let imageData = normalized.jpegData(compressionQuality: quality.compressionQuality) else { throw CocoaError(.fileWriteUnknown) }
        try imageData.write(to: imageURL, options: .atomic)
        let size = CGSize(width: 360, height: 360)
        let renderer = UIGraphicsImageRenderer(size: size)
        let thumb = renderer.image { _ in
            let scale = max(size.width / normalized.size.width, size.height / normalized.size.height)
            let drawSize = CGSize(width: normalized.size.width * scale, height: normalized.size.height * scale)
            normalized.draw(in: CGRect(
                x: (size.width - drawSize.width) / 2,
                y: (size.height - drawSize.height) / 2,
                width: drawSize.width,
                height: drawSize.height
            ))
        }
        guard let thumbData = thumb.jpegData(compressionQuality: 0.72) else { throw CocoaError(.fileWriteUnknown) }
        try thumbData.write(to: thumbURL, options: .atomic)
        return (relative(imageURL), relative(thumbURL))
    }
    func image(at path: String) -> UIImage? { UIImage(contentsOfFile: root.deletingLastPathComponent().appendingPathComponent(path).path) }
    func data(at path: String) -> Data? { try? Data(contentsOf: root.deletingLastPathComponent().appendingPathComponent(path)) }
    func exists(at path: String) -> Bool { fm.fileExists(atPath: root.deletingLastPathComponent().appendingPathComponent(path).path) }
    func totalBytes() -> Int64 {
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return enumerator.compactMap { $0 as? URL }.reduce(0) { total, url in
            total + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }
    func deleteAll() throws {
        if fm.fileExists(atPath: root.path) { try fm.removeItem(at: root) }
    }
    func delete(recordID: UUID) { try? fm.removeItem(at: root.appendingPathComponent(recordID.uuidString)) }
    func delete(photo: RecordPhoto) {
        let applicationSupport = root.deletingLastPathComponent()
        try? fm.removeItem(at: applicationSupport.appendingPathComponent(photo.imagePath))
        try? fm.removeItem(at: applicationSupport.appendingPathComponent(photo.thumbnailPath))
    }
    private func relative(_ url: URL) -> String { "RecordPhotos/" + url.pathComponents.suffix(2).joined(separator: "/") }
}

protocol MapSearchClient { func search(query: String, region: MKCoordinateRegion?) async throws -> [PlaceCandidate] }
struct PlaceCandidate: Identifiable, Hashable { let id: String; let name: String; let address: String; let latitude: Double; let longitude: Double; let category: String }
final class AppleMapSearchClient: MapSearchClient {
    func search(query: String, region: MKCoordinateRegion? = nil) async throws -> [PlaceCandidate] {
        let primary = try await runSearch(query: query, region: region)
        let supplemental = primary.count < 8
            ? (try? await runSearch(query: "\(query) 飲食店", region: region)) ?? []
            : []

        var seen = Set<String>()
        return (primary + supplemental).filter { seen.insert($0.id).inserted }.prefix(12).map { $0 }
    }

    private func runSearch(query: String, region: MKCoordinateRegion?) async throws -> [PlaceCandidate] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = region ?? MKCoordinateRegion(.world)
        request.resultTypes = .pointOfInterest
        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems.map { item in
            let coordinate = coordinate(for: item)
            return PlaceCandidate(
                id: identifier(for: item, coordinate: coordinate),
                name: item.name ?? "名称なし",
                address: address(for: item),
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                category: item.pointOfInterestCategory?.rawValue ?? ""
            )
        }
    }

    private func identifier(for item: MKMapItem, coordinate: CLLocationCoordinate2D) -> String {
        if #available(iOS 18.0, *), let identifier = item.identifier?.rawValue {
            return identifier
        }
        return "\(item.name ?? "")-\(coordinate.latitude)-\(coordinate.longitude)"
    }

    private func coordinate(for item: MKMapItem) -> CLLocationCoordinate2D {
        if #available(iOS 26.0, *) {
            return item.location.coordinate
        }
        return item.placemark.coordinate
    }

    private func address(for item: MKMapItem) -> String {
        if #available(iOS 26.0, *) {
            return item.addressRepresentations?.fullAddress(includingRegion: true, singleLine: true)
                ?? item.address?.fullAddress
                ?? ""
        }
        return item.placemark.title ?? ""
    }
}

protocol LocationService { var currentLocation: CLLocation? { get }; func request() }
@Observable final class DeviceLocationService: NSObject, LocationService, CLLocationManagerDelegate {
    private let manager = CLLocationManager(); private(set) var currentLocation: CLLocation?
    override init() { super.init(); manager.delegate = self }
    func request() { manager.requestWhenInUseAuthorization(); manager.requestLocation() }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) { currentLocation = locations.last }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

protocol ExportImportService { func csv(records: [RestaurantRecord], places: [Place], tags: [Tag]) -> String }
struct LocalExportImportService: ExportImportService {
    func csv(records: [RestaurantRecord], places: [Place], tags: [Tag]) -> String {
        let header = "店名,住所,状態,評価,訪問日,メモ,タグ\n"
        let rows = records.map { r -> String in let p = places.first { $0.id == r.placeID }; let names = tags.filter { r.tagIDs.contains($0.id) }.map(\.name).joined(separator: "|"); return [p?.name ?? "", p?.address ?? "", r.status.title, r.displayRating == 0 ? "" : r.ratingText, r.visitDate?.formatted(date: .numeric, time: .omitted) ?? "", r.memo, names].map(csv).joined(separator: ",") }
        return header + rows.joined(separator: "\n")
    }
    private func csv(_ text: String) -> String { "\"\(text.replacingOccurrences(of: "\"", with: "\"\""))\"" }
}
