import Foundation
import QuartzCore
import RealityKit
import os

// MARK: - Heightfield Models

struct HeightfieldMeta: Codable {
    let units: HeightfieldUnits?
    let grid: HeightfieldGrid
    let mask: HeightfieldMask?
}

struct HeightfieldUnits: Codable {
    let x: String
    let z: String
    let y: String
}

struct HeightfieldGrid: Codable {
    let nx: Int
    let nz: Int
    let resolutionFt: Double
    let xMinFt: Double
    let zMinFt: Double

    enum CodingKeys: String, CodingKey {
        case nx, nz
        case resolutionFt = "resolution_ft"
        case xMinFt = "x_min_ft"
        case zMinFt = "z_min_ft"
    }
}

struct HeightfieldMask: Codable {
    let format: String?
    let note: String?
}

struct HeightfieldData {
    let nx: Int
    let nz: Int
    let resolution: Double
    let xMin: Double
    let zMin: Double
    let heights: [Float]
}

// MARK: - Boundary Models

struct BoundaryData: Codable {
    let pointsXzFt: [BoundaryPoint]

    enum CodingKeys: String, CodingKey {
        case pointsXzFt = "points_xz_ft"
    }
}

struct BoundaryPoint: Codable {
    let x: Double
    let z: Double
}

// MARK: - Terrain Sampler

/// Bilinear interpolation of heightfield at arbitrary (xFt, zFt) positions.
/// All heights are returned relative to the mean, so the green is centered around y=0.
struct TerrainSampler {
    let data: HeightfieldData
    let meanHeight: Float

    init(_ data: HeightfieldData) {
        self.data = data
        let valid = data.heights.filter { !$0.isNaN }
        if valid.isEmpty {
            meanHeight = 0
        } else {
            meanHeight = valid.reduce(Float(0), +) / Float(valid.count)
        }
    }

    /// Height in feet relative to mean at given feet coordinates
    func heightAt(xFt: Double, zFt: Double) -> Float {
        let gx = (xFt - data.xMin) / data.resolution
        let gz = (zFt - data.zMin) / data.resolution

        let ix0 = max(0, min(data.nx - 2, Int(gx)))
        let iz0 = max(0, min(data.nz - 2, Int(gz)))

        let fx = max(0, min(1, Float(gx) - Float(ix0)))
        let fz = max(0, min(1, Float(gz) - Float(iz0)))

        let raw00 = data.heights[iz0 * data.nx + ix0]
        let raw10 = data.heights[iz0 * data.nx + ix0 + 1]
        let raw01 = data.heights[(iz0 + 1) * data.nx + ix0]
        let raw11 = data.heights[(iz0 + 1) * data.nx + ix0 + 1]

        // Replace NaN (outside boundary) with mean so surface stays flat there
        let h00 = raw00.isNaN ? meanHeight : raw00
        let h10 = raw10.isNaN ? meanHeight : raw10
        let h01 = raw01.isNaN ? meanHeight : raw01
        let h11 = raw11.isNaN ? meanHeight : raw11

        let h = h00 * (1 - fx) * (1 - fz)
              + h10 * fx * (1 - fz)
              + h01 * (1 - fx) * fz
              + h11 * fx * fz

        return h - meanHeight
    }

    /// Convert height-in-feet (relative to mean) to scene Y coordinate
    func sceneY(_ heightFt: Float) -> Float {
        heightFt * Constants.Scene3D.scaleFactor * Constants.Scene3D.heightExaggeration
    }

    /// Scene Y at given feet coordinates
    func sceneYAt(xFt: Double, zFt: Double) -> Float {
        sceneY(heightAt(xFt: xFt, zFt: zFt))
    }
}

// MARK: - Scene Controller

class SceneController {
    private let anchor: Entity
    private let pathPositions: [SIMD3<Float>]
    private let duration: TimeInterval
    private var animationTimer: Timer?
    private var animationStartTime: TimeInterval = 0

    init(anchor: Entity, pathPositions: [SIMD3<Float>], duration: TimeInterval) {
        self.anchor = anchor
        self.pathPositions = pathPositions
        self.duration = max(duration, 0.1)
    }

    func startAnimation() {
        guard pathPositions.count > 1 else { return }
        resetBall()
        animationStartTime = CACurrentMediaTime()
        animationTimer?.invalidate()
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func resetBall() {
        animationTimer?.invalidate()
        animationTimer = nil
        guard let ball = anchor.children.first(where: { $0.name == "ball" }),
              let first = pathPositions.first else { return }
        ball.position = first
    }

    private func tick() {
        guard let ball = anchor.children.first(where: { $0.name == "ball" }) else { return }

        let elapsed = CACurrentMediaTime() - animationStartTime
        if elapsed >= duration {
            if let last = pathPositions.last { ball.position = last }
            animationTimer?.invalidate()
            animationTimer = nil
            return
        }

        let t = elapsed / duration
        let floatIndex = t * Double(pathPositions.count - 1)
        let idx = min(Int(floatIndex), pathPositions.count - 2)
        let frac = Float(floatIndex - Double(idx))

        ball.position = pathPositions[idx] + (pathPositions[idx + 1] - pathPositions[idx]) * frac
    }
}

// MARK: - Green Scene Builder

/// Shared scene builder for constructing the 3D putting green visualization.
/// Used by both the non-AR (Putt3DView) and AR (PuttARView) views.
struct GreenSceneBuilder {
    let bestLine: BestLineResult
    let sampler: TerrainSampler?
    let boundary: [BoundaryPoint]?
    let greenWidth: Double
    let greenHeight: Double
    private let logger = Logger(subsystem: Constants.Logging.subsystem, category: "SceneBuilder")

    init(bestLine: BestLineResult, heightfield: HeightfieldData?, boundary: [BoundaryPoint]?, greenWidth: Double, greenHeight: Double) {
        self.bestLine = bestLine
        self.sampler = heightfield.map { TerrainSampler($0) }
        self.boundary = boundary
        self.greenWidth = greenWidth
        self.greenHeight = greenHeight
    }

    // MARK: - Build Full Scene

    func buildScene(on parent: Entity) {
        if let sampler = sampler, let terrain = buildTerrainMesh(sampler: sampler) {
            parent.addChild(terrain)
        } else {
            parent.addChild(buildFlatTerrain())
        }

        if let path = buildPathRibbon() {
            parent.addChild(path)
        }

        let ball = buildBall()
        ball.name = "ball"
        parent.addChild(ball)

        parent.addChild(buildFlag())
    }

    // MARK: - Compute Path Positions

    func computePathPositions() -> [SIMD3<Float>] {
        let S = Constants.Scene3D.scaleFactor
        return (0..<bestLine.pathXFt.count).map { i in
            let xFt = bestLine.pathXFt[i]
            let zFt = bestLine.pathZFt[i]
            let y: Float = sampler.map { $0.sceneYAt(xFt: xFt, zFt: zFt) + Constants.Scene3D.ballRadius }
                ?? Constants.Scene3D.ballRadius
            return SIMD3(Float(xFt) * S, y, -Float(zFt) * S)
        }
    }

    // MARK: - Camera Helpers

    func orbitCenter() -> SIMD3<Float> {
        let S = Constants.Scene3D.scaleFactor
        var center = SIMD3<Float>(
            Float(bestLine.ballXFt + bestLine.holeXFt) / 2 * S,
            0,
            -Float(bestLine.ballZFt + bestLine.holeZFt) / 2 * S
        )
        if let sampler = sampler {
            let cxFt = (bestLine.ballXFt + bestLine.holeXFt) / 2
            let czFt = (bestLine.ballZFt + bestLine.holeZFt) / 2
            center.y = sampler.sceneYAt(xFt: cxFt, zFt: czFt)
        }
        return center
    }

    func ballScenePosition() -> SIMD3<Float> {
        let S = Constants.Scene3D.scaleFactor
        return SIMD3<Float>(Float(bestLine.ballXFt) * S, 0, -Float(bestLine.ballZFt) * S)
    }

    func holeScenePosition() -> SIMD3<Float> {
        let S = Constants.Scene3D.scaleFactor
        return SIMD3<Float>(Float(bestLine.holeXFt) * S, 0, -Float(bestLine.holeZFt) * S)
    }

    // MARK: - Heightfield Loading

    static func loadHeightfield(from hole: Hole, logger: Logger) async -> HeightfieldData? {
        guard let jsonUrlString = hole.processedUrls?.heightfieldJson,
              let jsonUrl = URL(string: jsonUrlString),
              let binUrlString = hole.processedUrls?.heightfieldBin,
              let binUrl = URL(string: binUrlString) else {
            logger.warning("No heightfield URLs, using flat terrain")
            return nil
        }

        do {
            async let jsonFetch = URLSession.shared.data(from: jsonUrl)
            async let binFetch = URLSession.shared.data(from: binUrl)
            let (jsonData, _) = try await jsonFetch
            let (binData, _) = try await binFetch

            let meta = try JSONDecoder().decode(HeightfieldMeta.self, from: jsonData)
            let expectedCount = meta.grid.nx * meta.grid.nz
            let heights: [Float] = binData.withUnsafeBytes { raw in
                let buffer = raw.bindMemory(to: Float32.self)
                return Array(buffer.prefix(expectedCount))
            }
            logger.info("Heightfield: \(meta.grid.nx)x\(meta.grid.nz), \(heights.count) heights")

            return HeightfieldData(
                nx: meta.grid.nx, nz: meta.grid.nz,
                resolution: meta.grid.resolutionFt,
                xMin: meta.grid.xMinFt, zMin: meta.grid.zMinFt,
                heights: heights
            )
        } catch {
            logger.error("Failed to load heightfield: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Boundary Loading

    static func loadBoundary(from hole: Hole, logger: Logger) async -> [BoundaryPoint]? {
        guard let urlString = hole.sourceUrls?.boundary,
              let url = URL(string: urlString) else {
            logger.info("No boundary URL available")
            return nil
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let boundary = try JSONDecoder().decode(BoundaryData.self, from: data)
            logger.info("Boundary loaded: \(boundary.pointsXzFt.count) vertices")
            return boundary.pointsXzFt
        } catch {
            logger.error("Failed to load boundary: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Point-in-Polygon (Ray Casting)

    private static func pointInPolygon(x: Double, z: Double, polygon: [BoundaryPoint]) -> Bool {
        var inside = false
        let n = polygon.count
        var j = n - 1
        for i in 0..<n {
            let zi = polygon[i].z, xi = polygon[i].x
            let zj = polygon[j].z, xj = polygon[j].x
            if (zi > z) != (zj > z) {
                let intersectX = xj + (z - zj) / (zi - zj) * (xi - xj)
                if x < intersectX {
                    inside = !inside
                }
            }
            j = i
        }
        return inside
    }

    // MARK: - Private Build Methods

    private func buildFlatTerrain() -> ModelEntity {
        let S = Constants.Scene3D.scaleFactor
        let mesh = MeshResource.generatePlane(
            width: Float(greenWidth) * S,
            depth: Float(greenHeight) * S
        )
        var mat = SimpleMaterial()
        mat.color = .init(tint: Constants.Scene3D.greenColor)
        return ModelEntity(mesh: mesh, materials: [mat])
    }

    private func buildTerrainMesh(sampler: TerrainSampler) -> ModelEntity? {
        let d = sampler.data
        let S = Constants.Scene3D.scaleFactor
        let H = Constants.Scene3D.heightExaggeration

        // Classify each vertex as inside or outside the green boundary
        var vertexInside: [Bool] = []
        if let boundary = boundary, !boundary.isEmpty {
            vertexInside.reserveCapacity(d.nx * d.nz)
            for iz in 0..<d.nz {
                for ix in 0..<d.nx {
                    let xFt = d.xMin + Double(ix) * d.resolution
                    let zFt = d.zMin + Double(iz) * d.resolution
                    vertexInside.append(Self.pointInPolygon(x: xFt, z: zFt, polygon: boundary))
                }
            }
        }

        var positions: [SIMD3<Float>] = []
        positions.reserveCapacity(d.nx * d.nz)

        for iz in 0..<d.nz {
            for ix in 0..<d.nx {
                let xFt = d.xMin + Double(ix) * d.resolution
                let zFt = d.zMin + Double(iz) * d.resolution
                let rawH = d.heights[iz * d.nx + ix]
                let hFt = rawH.isNaN ? Float(0) : rawH - sampler.meanHeight

                positions.append(SIMD3(
                    Float(xFt) * S,
                    hFt * S * H,
                    -Float(zFt) * S
                ))
            }
        }
        // Fallback: if boundary classification is unusable, use NaN mask
        if vertexInside.count == d.nx * d.nz {
            let insideCount = vertexInside.filter { $0 }.count
            if insideCount == 0 || insideCount == vertexInside.count {
                vertexInside = d.heights.map { !$0.isNaN }
                let nanInside = vertexInside.filter { $0 }.count
                logger.info("Boundary classification unusable (inside=\(insideCount)/\(vertexInside.count)); using NaN mask (inside=\(nanInside))")
            } else {
                logger.info("Boundary classification inside=\(insideCount)/\(vertexInside.count)")
            }
        }

        // Normals: cross product of grid tangent vectors
        var normals: [SIMD3<Float>] = []
        normals.reserveCapacity(d.nx * d.nz)
        for iz in 0..<d.nz {
            for ix in 0..<d.nx {
                if ix > 0 && ix < d.nx - 1 && iz > 0 && iz < d.nz - 1 {
                    let tangentX = positions[iz * d.nx + (ix + 1)] - positions[iz * d.nx + (ix - 1)]
                    let tangentZ = positions[(iz + 1) * d.nx + ix] - positions[(iz - 1) * d.nx + ix]
                    var n = simd_normalize(simd_cross(tangentZ, tangentX))
                    if n.y < 0 { n = -n }
                    normals.append(n)
                } else {
                    normals.append(SIMD3(0, 1, 0))
                }
            }
        }

        // Split triangles into green (inside) and ground (outside) groups
        var greenIndices: [UInt32] = []
        var groundIndices: [UInt32] = []
        let totalQuads = (d.nx - 1) * (d.nz - 1)
        greenIndices.reserveCapacity(totalQuads * 6)
        groundIndices.reserveCapacity(totalQuads * 2)

        for iz in 0..<(d.nz - 1) {
            for ix in 0..<(d.nx - 1) {
                let tl = UInt32(iz * d.nx + ix)
                let tr = UInt32(iz * d.nx + ix + 1)
                let bl = UInt32((iz + 1) * d.nx + ix)
                let br = UInt32((iz + 1) * d.nx + ix + 1)
                let tri: [UInt32] = [tl, tr, bl, tr, br, bl]

                if !vertexInside.isEmpty {
                    let allInside = vertexInside[Int(tl)] && vertexInside[Int(tr)]
                                 && vertexInside[Int(bl)] && vertexInside[Int(br)]
                    if allInside {
                        greenIndices.append(contentsOf: tri)
                    } else {
                        groundIndices.append(contentsOf: tri)
                    }
                } else {
                    greenIndices.append(contentsOf: tri)
                }
            }
        }

        var greenMat = SimpleMaterial()
        greenMat.color = .init(tint: Constants.Scene3D.greenColor)

        // Single-material mesh if no boundary or no outside triangles
        if groundIndices.isEmpty {
            var desc = MeshDescriptor(name: "terrain")
            desc.positions = MeshBuffers.Positions(positions)
            desc.normals = MeshBuffers.Normals(normals)
            desc.primitives = .triangles(greenIndices)

            guard let mesh = try? MeshResource.generate(from: [desc]) else {
                logger.error("Failed to generate terrain mesh")
                return nil
            }
            return ModelEntity(mesh: mesh, materials: [greenMat])
        }

        // Two-material mesh: green surface + brown ground
        var greenDesc = MeshDescriptor(name: "terrain-green")
        greenDesc.positions = MeshBuffers.Positions(positions)
        greenDesc.normals = MeshBuffers.Normals(normals)
        greenDesc.primitives = .triangles(greenIndices)

        var groundDesc = MeshDescriptor(name: "terrain-ground")
        groundDesc.positions = MeshBuffers.Positions(positions)
        groundDesc.normals = MeshBuffers.Normals(normals)
        groundDesc.primitives = .triangles(groundIndices)

        var groundMat = SimpleMaterial()
        groundMat.color = .init(tint: Constants.Scene3D.groundColor)

        guard let mesh = try? MeshResource.generate(from: [greenDesc, groundDesc]) else {
            logger.error("Failed to generate two-material terrain mesh")
            return nil
        }
        return ModelEntity(mesh: mesh, materials: [greenMat, groundMat])
    }

    private func buildPathRibbon() -> ModelEntity? {
        let count = bestLine.pathXFt.count
        guard count > 1 else { return nil }

        let S = Constants.Scene3D.scaleFactor
        let halfW = Constants.Scene3D.pathWidth / 2

        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        positions.reserveCapacity(count * 2)
        normals.reserveCapacity(count * 2)

        for i in 0..<count {
            let xFt = bestLine.pathXFt[i]
            let zFt = bestLine.pathZFt[i]
            let sceneX = Float(xFt) * S
            let sceneZ = -Float(zFt) * S
            let sceneY: Float = sampler.map { $0.sceneYAt(xFt: xFt, zFt: zFt) + Constants.Scene3D.pathOffset }
                ?? Constants.Scene3D.pathOffset

            // Tangent direction in scene space (Z is negated)
            let dx: Double
            let dz: Double
            if i == 0 {
                dx = bestLine.pathXFt[1] - bestLine.pathXFt[0]
                dz = -(bestLine.pathZFt[1] - bestLine.pathZFt[0])
            } else if i == count - 1 {
                dx = bestLine.pathXFt[i] - bestLine.pathXFt[i - 1]
                dz = -(bestLine.pathZFt[i] - bestLine.pathZFt[i - 1])
            } else {
                dx = bestLine.pathXFt[i + 1] - bestLine.pathXFt[i - 1]
                dz = -(bestLine.pathZFt[i + 1] - bestLine.pathZFt[i - 1])
            }

            // Perpendicular: rotate tangent 90 degrees in XZ plane
            let len = sqrt(Float(dx * dx + dz * dz))
            let perpX: Float
            let perpZ: Float
            if len > 0.001 {
                perpX = -Float(dz) / len * halfW
                perpZ = Float(dx) / len * halfW
            } else {
                perpX = 0
                perpZ = halfW
            }

            positions.append(SIMD3(sceneX + perpX, sceneY, sceneZ + perpZ))
            positions.append(SIMD3(sceneX - perpX, sceneY, sceneZ - perpZ))
            normals.append(SIMD3(0, 1, 0))
            normals.append(SIMD3(0, 1, 0))
        }

        var indices: [UInt32] = []
        indices.reserveCapacity((count - 1) * 6)
        for i in 0..<(count - 1) {
            let v0 = UInt32(i * 2)
            let v1 = UInt32(i * 2 + 1)
            let v2 = UInt32((i + 1) * 2)
            let v3 = UInt32((i + 1) * 2 + 1)
            indices.append(contentsOf: [v0, v2, v1, v1, v2, v3])
        }

        var desc = MeshDescriptor(name: "path")
        desc.positions = MeshBuffers.Positions(positions)
        desc.normals = MeshBuffers.Normals(normals)
        desc.primitives = .triangles(indices)

        guard let mesh = try? MeshResource.generate(from: [desc]) else { return nil }

        var mat = SimpleMaterial()
        mat.color = .init(tint: .systemBlue)
        return ModelEntity(mesh: mesh, materials: [mat])
    }

    private func buildBall() -> ModelEntity {
        let S = Constants.Scene3D.scaleFactor
        let mesh = MeshResource.generateSphere(radius: Constants.Scene3D.ballRadius)
        var mat = SimpleMaterial()
        mat.color = .init(tint: .white)
        mat.metallic = .float(0.1)
        mat.roughness = .float(0.3)

        let ball = ModelEntity(mesh: mesh, materials: [mat])
        let xFt = bestLine.ballXFt
        let zFt = bestLine.ballZFt
        let y: Float = sampler.map { $0.sceneYAt(xFt: xFt, zFt: zFt) + Constants.Scene3D.ballRadius }
            ?? Constants.Scene3D.ballRadius
        ball.position = SIMD3(Float(xFt) * S, y, -Float(zFt) * S)
        logger.info("Ball at feet(\(xFt), \(zFt)), hole at feet(\(bestLine.holeXFt), \(bestLine.holeZFt))")
        return ball
    }

    private func buildFlag() -> Entity {
        let S = Constants.Scene3D.scaleFactor
        let root = Entity()

        let xFt = bestLine.holeXFt
        let zFt = bestLine.holeZFt
        let baseY: Float = sampler?.sceneYAt(xFt: xFt, zFt: zFt) ?? 0

        // Pole
        let poleMesh = MeshResource.generateBox(
            width: Constants.Scene3D.poleDiameter,
            height: Constants.Scene3D.poleHeight,
            depth: Constants.Scene3D.poleDiameter
        )
        var poleMat = SimpleMaterial()
        poleMat.color = .init(tint: .white)
        let pole = ModelEntity(mesh: poleMesh, materials: [poleMat])
        pole.position = SIMD3(0, Constants.Scene3D.poleHeight / 2, 0)
        root.addChild(pole)

        // Cloth
        let clothMesh = MeshResource.generateBox(
            width: Constants.Scene3D.clothWidth,
            height: Constants.Scene3D.clothHeight,
            depth: 0.02
        )
        var clothMat = SimpleMaterial()
        clothMat.color = .init(tint: .red)
        let cloth = ModelEntity(mesh: clothMesh, materials: [clothMat])
        cloth.position = SIMD3(
            Constants.Scene3D.clothWidth / 2,
            Constants.Scene3D.poleHeight - Constants.Scene3D.clothHeight / 2 - 0.05,
            0
        )
        root.addChild(cloth)

        // Hole disc
        let holeMesh = MeshResource.generateBox(
            width: Constants.Scene3D.holeDiscSize,
            height: 0.01,
            depth: Constants.Scene3D.holeDiscSize
        )
        var holeMat = SimpleMaterial()
        holeMat.color = .init(tint: .black)
        let holeDisc = ModelEntity(mesh: holeMesh, materials: [holeMat])
        holeDisc.position = SIMD3(0, 0.005, 0)
        root.addChild(holeDisc)

        root.position = SIMD3(Float(xFt) * S, baseY, -Float(zFt) * S)
        return root
    }
}
