import Foundation

struct Hole: Codable {
    let courseId: String
    let holeNum: Int
    let greenWidthFt: Double?
    let greenHeightFt: Double?
    let hasSource: Bool?
    let hasProcessed: Bool?
    let sourceUrls: SourceUrls?
    let processedUrls: ProcessedUrls?

    struct Response: Codable {
        let hole: Hole
    }
}

struct SourceUrls: Codable {
    let map: String?
    let contour: String?
    let boundary: String?
    let contours: String?

    enum CodingKeys: String, CodingKey {
        case map = "map.png"
        case contour = "contour.png"
        case boundary = "boundary.json"
        case contours = "contours.json"
    }
}

struct ProcessedUrls: Codable {
    let heightfieldJson: String?
    let heightfieldBin: String?

    enum CodingKeys: String, CodingKey {
        case heightfieldJson = "heightfield.json"
        case heightfieldBin = "heightfield.bin"
    }
}
