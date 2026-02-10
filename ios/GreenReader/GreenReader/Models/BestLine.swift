import Foundation

struct BestLineRequest: Codable {
    let ballXFt: Double
    let ballZFt: Double
    let holeXFt: Double?
    let holeZFt: Double?
    let stimpFt: Double?
}

struct BestLineResult: Codable {
    let ballXFt: Double
    let ballZFt: Double
    let holeXFt: Double
    let holeZFt: Double
    let stimpFt: Double
    let aimOffsetDeg: Double
    let speedFps: Double
    let v0XFps: Double
    let v0ZFps: Double
    let holed: Bool
    let missFt: Double
    let tEndS: Double
    let pathXFt: [Double]
    let pathZFt: [Double]
    let pathYFt: [Double]
}
