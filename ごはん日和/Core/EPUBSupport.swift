import Foundation
import SwiftData

nonisolated enum EPUBError: LocalizedError {
    case invalidFile
    case unsupportedCompression
    case fileTooLarge
    case noRecords
    case missingPhoto

    var errorDescription: String? {
        switch self {
        case .invalidFile: "EPUBファイルを読み込めませんでした。ファイルが破損している可能性があります。"
        case .unsupportedCompression: "このEPUBで使われている圧縮方式には対応していません。"
        case .fileTooLarge: "EPUBのサイズまたは内容が大きすぎます。"
        case .noRecords: "取り込める訪問記録が見つかりませんでした。"
        case .missingPhoto: "一部の写真データを読み込めませんでした。"
        }
    }
}

nonisolated struct EPUBVisit: Sendable {
    let placeName: String
    let address: String
    let ratingHalfSteps: Int
    let visitDate: Date?
    let memo: String
    let tagNames: [String]
    let photos: [Data]
}

nonisolated struct EPUBImport: Sendable {
    let visits: [EPUBVisit]

    var photoCount: Int { visits.reduce(0) { $0 + $1.photos.count } }
}

nonisolated struct EPUBImportResult {
    let importedRecordCount: Int
    let importedPhotoCount: Int
    let skippedDuplicateCount: Int
}

nonisolated struct EPUBService {
    @MainActor
    func encode(
        records: [RestaurantRecord],
        places: [Place],
        tags: [Tag],
        photos: [RecordPhoto]
    ) throws -> Data {
        let placeByID = Dictionary(uniqueKeysWithValues: places.map { ($0.id, $0) })
        let tagByID = Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0) })
        let photosByRecordID = Dictionary(grouping: photos, by: \.recordID)
        let photoStore = LocalPhotoStore()

        let exports = try records
            .filter { !$0.isDeleted && $0.status == .visited }
            .sorted {
                let leftDate = $0.visitDate ?? $0.createdAt
                let rightDate = $1.visitDate ?? $1.createdAt
                return leftDate == rightDate ? $0.createdAt > $1.createdAt : leftDate > rightDate
            }
            .map { record -> ExportVisit in
                guard let place = placeByID[record.placeID] else { throw EPUBError.invalidFile }
                let imageData = try (photosByRecordID[record.id] ?? [])
                    .sorted { $0.order < $1.order }
                    .map { photo in
                        guard let data = photoStore.data(at: photo.imagePath) else { throw EPUBError.missingPhoto }
                        return data
                    }
                return ExportVisit(
                    id: record.id,
                    placeName: place.name,
                    address: place.address,
                    ratingHalfSteps: record.ratingHalfSteps > 0 ? record.ratingHalfSteps : record.rating * 2,
                    visitDate: record.visitDate,
                    memo: record.memo,
                    tagNames: record.tagIDs.compactMap { tagByID[$0]?.name },
                    photos: imageData
                )
            }
        guard !exports.isEmpty else { throw EPUBError.noRecords }
        return try makeArchive(for: exports)
    }

    func decode(_ data: Data) throws -> EPUBImport {
        let files = try ZIPContainer.contents(of: data)
        guard files["mimetype"].flatMap({ String(data: $0, encoding: .utf8) })?
            .trimmingCharacters(in: .whitespacesAndNewlines) == "application/epub+zip" else {
            throw EPUBError.invalidFile
        }

        let packagePath = packagePath(in: files)
        let documentPaths = packagePath.flatMap { path -> [String]? in
            guard let packageData = files[path], let package = OPFParser.parse(packageData) else { return nil }
            return package.spine.compactMap { package.manifest[$0] }
                .filter { $0.mediaType == "application/xhtml+xml" && !$0.properties.contains("nav") }
                .map { resolvedPath($0.href, relativeTo: path) }
        } ?? files.keys.filter { $0.lowercased().hasSuffix(".xhtml") && !$0.lowercased().hasSuffix("nav.xhtml") }.sorted()

        var visits: [EPUBVisit] = []
        for documentPath in documentPaths {
            guard let chapterData = files[documentPath], let chapter = ChapterParser.parse(chapterData) else { continue }
            let imageData = chapter.photoPaths.compactMap { photoPath -> Data? in
                files[resolvedPath(photoPath, relativeTo: documentPath)]
            }
            guard imageData.count == chapter.photoPaths.count else { throw EPUBError.missingPhoto }
            visits.append(EPUBVisit(
                placeName: chapter.placeName,
                address: chapter.address,
                ratingHalfSteps: chapter.ratingHalfSteps,
                visitDate: chapter.visitDate,
                memo: chapter.memo,
                tagNames: chapter.tagNames,
                photos: imageData
            ))
        }
        guard !visits.isEmpty else { throw EPUBError.noRecords }
        return EPUBImport(visits: visits)
    }

    @MainActor
    func apply(
        _ imported: EPUBImport,
        context: ModelContext,
        currentPlaces: [Place],
        currentRecords: [RestaurantRecord],
        currentTags: [Tag]
    ) throws -> EPUBImportResult {
        let photoStore = LocalPhotoStore()
        var stagedPhotos: [RecordPhoto] = []
        var placesByKey = currentPlaces.reduce(into: [String: Place]()) {
            $0[placeKey(name: $1.name, address: $1.address)] = $1
        }
        var placesByID = Dictionary(uniqueKeysWithValues: currentPlaces.map { ($0.id, $0) })
        var tagsByName = currentTags.reduce(into: [String: Tag]()) { $0[$1.normalizedName] = $1 }
        var fingerprints = Set(currentRecords.filter { !$0.isDeleted }.compactMap { record -> String? in
            guard let place = placesByID[record.placeID] else { return nil }
            return recordFingerprint(placeName: place.name, address: place.address, date: record.visitDate, memo: record.memo)
        })
        var importedRecords = 0
        var importedPhotos = 0
        var skippedDuplicates = 0

        do {
            for visit in imported.visits {
                let fingerprint = recordFingerprint(
                    placeName: visit.placeName,
                    address: visit.address,
                    date: visit.visitDate,
                    memo: visit.memo
                )
                guard fingerprints.insert(fingerprint).inserted else {
                    skippedDuplicates += 1
                    continue
                }

                let key = placeKey(name: visit.placeName, address: visit.address)
                let place: Place
                if let existing = placesByKey[key] {
                    place = existing
                } else {
                    let newPlace = Place(name: visit.placeName, address: visit.address)
                    context.insert(newPlace)
                    placesByKey[key] = newPlace
                    placesByID[newPlace.id] = newPlace
                    place = newPlace
                }

                var tagIDs: [UUID] = []
                for rawName in visit.tagNames {
                    let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { continue }
                    let normalized = name.lowercased()
                    let tag: Tag
                    if let existing = tagsByName[normalized] {
                        tag = existing
                    } else {
                        let newTag = Tag(name: name)
                        context.insert(newTag)
                        tagsByName[normalized] = newTag
                        tag = newTag
                    }
                    if !tagIDs.contains(tag.id) { tagIDs.append(tag.id) }
                }

                let record = RestaurantRecord(placeID: place.id, status: .visited)
                record.ratingHalfSteps = visit.ratingHalfSteps
                record.rating = visit.ratingHalfSteps / 2
                record.visitDate = visit.visitDate
                record.memo = visit.memo
                record.tagIDs = tagIDs
                context.insert(record)

                for (order, imageData) in visit.photos.enumerated() {
                    let saved = try photoStore.save(imageData, recordID: record.id, order: order)
                    let photo = RecordPhoto(
                        recordID: record.id,
                        imagePath: saved.imagePath,
                        thumbnailPath: saved.thumbnailPath,
                        order: order
                    )
                    context.insert(photo)
                    stagedPhotos.append(photo)
                    importedPhotos += 1
                }
                importedRecords += 1
            }
            try context.save()
        } catch {
            stagedPhotos.forEach { photoStore.delete(photo: $0) }
            context.rollback()
            throw error
        }

        return EPUBImportResult(
            importedRecordCount: importedRecords,
            importedPhotoCount: importedPhotos,
            skippedDuplicateCount: skippedDuplicates
        )
    }

    private struct ExportVisit {
        let id: UUID
        let placeName: String
        let address: String
        let ratingHalfSteps: Int
        let visitDate: Date?
        let memo: String
        let tagNames: [String]
        let photos: [Data]
    }

    private func makeArchive(for visits: [ExportVisit]) throws -> Data {
        let bookID = UUID().uuidString.lowercased()
        let dateTitle = Self.dateString(from: .now).replacingOccurrences(of: "-", with: "/")
        let modified = ISO8601DateFormatter().string(from: .now)
        var entries: [ZIPContainer.Entry] = [
            .init(path: "mimetype", data: try utf8("application/epub+zip"), shouldCompress: false),
            .init(path: "META-INF/container.xml", data: try utf8(Self.containerXML)),
            .init(path: "EPUB/styles/main.css", data: try utf8(Self.styleSheet))
        ]
        var manifestItems = [
            "<item href=\"styles/main.css\" id=\"style\" media-type=\"text/css\"/>",
            "<item href=\"index.xhtml\" id=\"index\" media-type=\"application/xhtml+xml\"/>",
            "<item href=\"nav.xhtml\" id=\"nav\" media-type=\"application/xhtml+xml\" properties=\"nav\"/>",
            "<item href=\"toc.ncx\" id=\"ncx\" media-type=\"application/x-dtbncx+xml\"/>"
        ]
        var spineItems = ["<itemref idref=\"index\"/>"]
        var navigationItems: [String] = []

        for (index, visit) in visits.enumerated() {
            let chapterName = "chapter_\(visit.id.uuidString.lowercased()).xhtml"
            let chapterID = "chapter_\(index)"
            var imagePaths: [String] = []
            for (photoIndex, photoData) in visit.photos.enumerated() {
                let imageName = "img-\(visit.id.uuidString.lowercased())-\(photoIndex + 1).jpg"
                let imagePath = "images/\(imageName)"
                imagePaths.append(imagePath)
                entries.append(.init(path: "EPUB/\(imagePath)", data: photoData, shouldCompress: false))
                manifestItems.append("<item href=\"\(imagePath)\" id=\"image_\(index)_\(photoIndex)\" media-type=\"image/jpeg\"/>")
            }
            entries.append(.init(path: "EPUB/\(chapterName)", data: try utf8(chapterXML(for: visit, imagePaths: imagePaths))))
            manifestItems.append("<item href=\"\(chapterName)\" id=\"\(chapterID)\" media-type=\"application/xhtml+xml\"/>")
            spineItems.append("<itemref idref=\"\(chapterID)\"/>")
            navigationItems.append("<li><a href=\"\(chapterName)\">\(xmlEscaped(visit.placeName))</a></li>")
        }

        let title = "行った記録 \(dateTitle)作成"
        let navigationList = navigationItems.joined(separator: "\n")
        entries.append(.init(path: "EPUB/index.xhtml", data: try utf8(indexXML(title: title, items: navigationList))))
        entries.append(.init(path: "EPUB/nav.xhtml", data: try utf8(navXML(title: title, items: navigationList))))
        entries.append(.init(path: "EPUB/toc.ncx", data: try utf8(ncxXML(bookID: bookID, title: title, visits: visits))))

        let package = """
        <?xml version="1.0" encoding="utf-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" unique-identifier="book-id" version="3.0">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:identifier id="book-id">\(bookID)</dc:identifier>
            <dc:title>\(xmlEscaped(title))</dc:title>
            <dc:creator>ごはん日和</dc:creator>
            <dc:language>ja</dc:language>
            <meta property="dcterms:modified">\(modified)</meta>
          </metadata>
          <manifest>
            \(manifestItems.joined(separator: "\n    "))
          </manifest>
          <spine toc="ncx">
            \(spineItems.joined(separator: "\n    "))
          </spine>
        </package>
        """
        entries.append(.init(path: "EPUB/content.opf", data: try utf8(package)))
        return try ZIPContainer.archive(entries: entries)
    }

    private func chapterXML(for visit: ExportVisit, imagePaths: [String]) -> String {
        let rating = min(max(visit.ratingHalfSteps, 0), 10)
        let ratingValue = Double(rating) / 2
        let filledStars = Int(ratingValue.rounded())
        let stars = String(repeating: "★", count: filledStars) + String(repeating: "☆", count: 5 - filledStars)
        let ratingText = ratingValue == ratingValue.rounded() ? String(Int(ratingValue)) : String(format: "%.1f", ratingValue)
        let photoMarkup = imagePaths.map {
            "<a class=\"photo-thumb\" href=\"\($0)\"><img src=\"\($0)\" alt=\"photo\"/></a>"
        }.joined(separator: "\n")
        let tagMarkup = visit.tagNames.map { "<span>#\(xmlEscaped($0))</span>" }.joined(separator: " ")
        let date = visit.visitDate.map { Self.dateString(from: $0) } ?? ""
        return """
        <?xml version="1.0" encoding="utf-8"?>
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" lang="ja" xml:lang="ja">
          <head><title>\(xmlEscaped(visit.placeName))</title><link href="styles/main.css" rel="stylesheet" type="text/css"/></head>
          <body><div class="chapter-page"><div class="box">
            <p class="visit-title">\(xmlEscaped(visit.placeName))</p>
            <div class="photo-strip">\(photoMarkup)</div>
            <div class="meta">\(stars) \(ratingText)</div>
            <div class="kv"><h2>訪問日</h2><p>\(date)</p></div>
            <div class="kv"><h2>メモ</h2><p>\(xmlEscaped(visit.memo))</p></div>
            <div class="kv"><h2>タグ</h2><p class="tags">\(tagMarkup)</p></div>
            <div class="kv"><h2>住所</h2><p>\(xmlEscaped(visit.address))</p></div>
          </div></div></body>
        </html>
        """
    }

    private func indexXML(title: String, items: String) -> String {
        """
        <?xml version="1.0" encoding="utf-8"?>
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml" lang="ja"><head><title>\(xmlEscaped(title))</title><link href="styles/main.css" rel="stylesheet" type="text/css"/></head><body><main><h1>\(xmlEscaped(title))</h1><ol>\(items)</ol></main></body></html>
        """
    }

    private func navXML(title: String, items: String) -> String {
        """
        <?xml version="1.0" encoding="utf-8"?>
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" lang="ja"><head><title>目次</title></head><body><nav epub:type="toc"><h1>\(xmlEscaped(title))</h1><ol>\(items)</ol></nav></body></html>
        """
    }

    private func ncxXML(bookID: String, title: String, visits: [ExportVisit]) -> String {
        let points = visits.enumerated().map { index, visit in
            "<navPoint id=\"navPoint-\(index + 1)\" playOrder=\"\(index + 1)\"><navLabel><text>\(xmlEscaped(visit.placeName))</text></navLabel><content src=\"chapter_\(visit.id.uuidString.lowercased()).xhtml\"/></navPoint>"
        }.joined(separator: "\n")
        return """
        <?xml version="1.0" encoding="utf-8"?>
        <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1"><head><meta name="dtb:uid" content="\(bookID)"/></head><docTitle><text>\(xmlEscaped(title))</text></docTitle><navMap>\(points)</navMap></ncx>
        """
    }

    private func packagePath(in files: [String: Data]) -> String? {
        if let container = files["META-INF/container.xml"], let parsed = ContainerParser.parse(container) {
            return parsed
        }
        return files.keys.first { $0.lowercased().hasSuffix(".opf") }
    }

    private func resolvedPath(_ path: String, relativeTo basePath: String) -> String {
        let cleanPath = path.removingPercentEncoding ?? path
        let pathWithoutFragment = cleanPath.split(separator: "#", maxSplits: 1).first.map(String.init) ?? cleanPath
        let baseDirectory = (basePath as NSString).deletingLastPathComponent
        let combinedPath = (("/" + baseDirectory) as NSString).appendingPathComponent(pathWithoutFragment)
        return (combinedPath as NSString).standardizingPath
            .dropFirst()
            .description
    }

    private func utf8(_ value: String) throws -> Data {
        guard let data = value.data(using: .utf8) else { throw EPUBError.invalidFile }
        return data
    }

    private func xmlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private func placeKey(name: String, address: String) -> String {
        "\(normalized(name))|\(normalized(address))"
    }

    private func recordFingerprint(placeName: String, address: String, date: Date?, memo: String) -> String {
        let dateText = date.map { Self.dateString(from: $0) } ?? ""
        return "\(placeKey(name: placeName, address: address))|\(dateText)|\(normalized(memo))"
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    fileprivate static func dateString(from date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else { return "" }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    fileprivate static func date(from value: String) -> Date? {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.date(from: DateComponents(
            timeZone: .current,
            year: parts[0],
            month: parts[1],
            day: parts[2]
        ))
    }

    private static let containerXML = """
    <?xml version="1.0" encoding="utf-8"?>
    <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="EPUB/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>
    """

    private static let styleSheet = """
    body { font-family: -apple-system, sans-serif; color: #2d211c; background: #fffaf4; line-height: 1.6; }
    main, .chapter-page { max-width: 48rem; margin: 0 auto; padding: 1.5rem; }
    .box { background: white; border-radius: 1rem; padding: 1.25rem; }
    .visit-title { font-size: 1.6rem; font-weight: 700; margin-top: 0; }
    .photo-strip { display: flex; flex-wrap: wrap; gap: .5rem; }
    .photo-thumb img { width: 10rem; height: 10rem; object-fit: cover; border-radius: .5rem; }
    .meta { color: #e36f32; font-weight: 700; margin: 1rem 0; }
    .kv h2 { font-size: .8rem; color: #77655b; margin-bottom: 0; }
    .kv p { margin-top: .2rem; white-space: pre-wrap; }
    .tags span { display: inline-block; margin-right: .4rem; }
    """
}

nonisolated private final class ContainerParser: NSObject, XMLParserDelegate {
    private var rootFilePath: String?

    static func parse(_ data: Data) -> String? {
        let delegate = ContainerParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { return nil }
        return delegate.rootFilePath
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if elementName == "rootfile" { rootFilePath = attributeDict["full-path"] }
    }
}

nonisolated private final class OPFParser: NSObject, XMLParserDelegate {
    struct Item {
        let href: String
        let mediaType: String
        let properties: String
    }

    private(set) var manifest: [String: Item] = [:]
    private(set) var spine: [String] = []

    static func parse(_ data: Data) -> OPFParser? {
        let delegate = OPFParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { return nil }
        return delegate
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if elementName == "item", let id = attributeDict["id"], let href = attributeDict["href"] {
            manifest[id] = Item(
                href: href,
                mediaType: attributeDict["media-type"] ?? "",
                properties: attributeDict["properties"] ?? ""
            )
        } else if elementName == "itemref", let id = attributeDict["idref"] {
            spine.append(id)
        }
    }
}

nonisolated private final class ChapterParser: NSObject, XMLParserDelegate {
    private enum Capture {
        case title
        case meta
        case label
        case value
        case tag
    }

    private var stack: [String] = []
    private var capture: Capture?
    private var captureDepth = 0
    private var capturedText = ""
    private var keyValueDepth: Int?
    private var tagParagraphDepth: Int?
    private var currentLabel = ""
    private var values: [String: String] = [:]
    private var meta = ""
    private var tags: [String] = []
    private(set) var placeName = ""
    private(set) var photoPaths: [String] = []

    var address: String { values["住所"] ?? "" }
    var memo: String { values["メモ"] ?? "" }
    var tagNames: [String] { tags }
    var visitDate: Date? { values["訪問日"].flatMap(EPUBService.date(from:)) }
    var ratingHalfSteps: Int {
        let number = meta.split(whereSeparator: \.isWhitespace).reversed().compactMap { Double($0) }.first ?? 0
        return min(max(Int((number * 2).rounded()), 0), 10)
    }

    static func parse(_ data: Data) -> ChapterParser? {
        let delegate = ChapterParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse(), !delegate.placeName.isEmpty else { return nil }
        return delegate
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        stack.append(elementName)
        let depth = stack.count
        let cssClass = attributeDict["class"] ?? ""

        if elementName == "div", cssClass.split(separator: " ").contains("kv") {
            keyValueDepth = depth
            currentLabel = ""
        } else if elementName == "p", cssClass.split(separator: " ").contains("visit-title") {
            begin(.title, at: depth)
        } else if elementName == "div", cssClass.split(separator: " ").contains("meta") {
            begin(.meta, at: depth)
        } else if keyValueDepth != nil, elementName == "h2" {
            begin(.label, at: depth)
        } else if keyValueDepth != nil, elementName == "p" {
            if currentLabel == "タグ" {
                tagParagraphDepth = depth
            } else {
                begin(.value, at: depth)
            }
        } else if tagParagraphDepth != nil, elementName == "span" {
            begin(.tag, at: depth)
        }

        if elementName == "img", let source = attributeDict["src"], !source.isEmpty {
            photoPaths.append(source)
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if capture != nil { capturedText += string }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let depth = stack.count
        if capture != nil, captureDepth == depth { finishCapture() }
        if tagParagraphDepth == depth { tagParagraphDepth = nil }
        if keyValueDepth == depth {
            keyValueDepth = nil
            currentLabel = ""
        }
        if !stack.isEmpty { stack.removeLast() }
    }

    private func begin(_ value: Capture, at depth: Int) {
        capture = value
        captureDepth = depth
        capturedText = ""
    }

    private func finishCapture() {
        let text = capturedText.trimmingCharacters(in: .whitespacesAndNewlines)
        switch capture {
        case .title: placeName = text
        case .meta: meta = text
        case .label: currentLabel = text
        case .value: values[currentLabel] = text
        case .tag:
            let name = text.hasPrefix("#") ? String(text.dropFirst()) : text
            if !name.isEmpty { tags.append(name) }
        case nil: break
        }
        capture = nil
        capturedText = ""
    }
}
