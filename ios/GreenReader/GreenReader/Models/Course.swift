import Foundation

struct Course: Codable, Identifiable {
    let id: String
    let name: String
    let city: String?
    let state: String?
    let numHoles: Int?

    struct ListResponse: Codable {
        let courses: [Course]
    }

    struct DetailResponse: Codable {
        let course: CourseDetail
    }
}

struct CourseDetail: Codable {
    let id: String
    let name: String
    let numHoles: Int?
    let holes: [HoleSummary]?
}

struct HoleSummary: Codable, Identifiable {
    let holeNum: Int
    let greenWidthFt: Double?
    let greenHeightFt: Double?
    let hasSource: Bool?
    let hasProcessed: Bool?

    var id: Int { holeNum }
}
