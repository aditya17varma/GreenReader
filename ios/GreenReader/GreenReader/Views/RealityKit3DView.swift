import SwiftUI
import RealityKit
import os

// MARK: - Putt3DView

struct Putt3DView: View {
    let bestLine: BestLineResult
    let hole: Hole
    let onDismiss: () -> Void

    @State private var isLoading = true
    @State private var heightfieldData: HeightfieldData?
    @State private var sceneController: SceneController?
    private let logger = Logger(subsystem: Constants.Logging.subsystem, category: "Putt3DView")

    var body: some View {
        ZStack {
            if isLoading {
                Color.black.ignoresSafeArea()
                VStack {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                    Text("Loading terrain...")
                        .foregroundColor(.white)
                        .padding(.top)
                }
            } else {
                RealityKitContainer(
                    bestLine: bestLine,
                    heightfield: heightfieldData,
                    greenWidth: hole.greenWidthFt ?? 100,
                    greenHeight: hole.greenHeightFt ?? 80,
                    onControllerReady: { sceneController = $0 }
                )
                .ignoresSafeArea()
            }

            // Overlay controls
            VStack {
                HStack {
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.largeTitle)
                            .foregroundColor(.white)
                            .shadow(radius: 4)
                    }
                    .padding()
                }
                Spacer()

                if !isLoading {
                    HStack(spacing: 12) {
                        Button(action: { sceneController?.startAnimation() }) {
                            HStack {
                                Image(systemName: "play.fill")
                                Text("Roll")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.borderedProminent)

                        Button(action: { sceneController?.resetBall() }) {
                            HStack {
                                Image(systemName: "arrow.counterclockwise")
                                Text("Reset")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 6)

                    HStack(spacing: 20) {
                        VStack {
                            Text("Aim").font(.caption).foregroundColor(.secondary)
                            Text("\(abs(bestLine.aimOffsetDeg), specifier: "%.1f")°")
                                .font(.headline).foregroundColor(.white)
                            Text(bestLine.aimOffsetDeg > 0 ? "left" : "right")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        Divider().frame(height: 40)
                        VStack {
                            Text("Speed").font(.caption).foregroundColor(.secondary)
                            Text("\(bestLine.speedFps, specifier: "%.1f")")
                                .font(.headline).foregroundColor(.white)
                            Text("ft/s").font(.caption).foregroundColor(.secondary)
                        }
                        Divider().frame(height: 40)
                        VStack {
                            Text("Result").font(.caption).foregroundColor(.secondary)
                            if bestLine.holed {
                                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                                Text("Holed!").font(.caption).foregroundColor(.green)
                            } else {
                                Text("\(bestLine.missFt, specifier: "%.1f") ft")
                                    .font(.headline).foregroundColor(.orange)
                                Text("miss").font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)
                    .padding()
                }
            }
        }
        .task { await loadHeightfield() }
    }

    private func loadHeightfield() async {
        guard let jsonUrlString = hole.processedUrls?.heightfieldJson,
              let jsonUrl = URL(string: jsonUrlString),
              let binUrlString = hole.processedUrls?.heightfieldBin,
              let binUrl = URL(string: binUrlString) else {
            logger.warning("No heightfield URLs, using flat terrain")
            isLoading = false
            return
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

            heightfieldData = HeightfieldData(
                nx: meta.grid.nx, nz: meta.grid.nz,
                resolution: meta.grid.resolutionFt,
                xMin: meta.grid.xMinFt, zMin: meta.grid.zMinFt,
                heights: heights
            )
        } catch {
            logger.error("Failed to load heightfield: \(error.localizedDescription)")
        }
        isLoading = false
    }
}

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

// MARK: - Terrain Sampler

/// Bilinear interpolation of heightfield at arbitrary (xFt, zFt) positions.
/// All heights are returned relative to the mean, so the green is centered around y=0.
struct TerrainSampler {
    let data: HeightfieldData
    let meanHeight: Float

    init(_ data: HeightfieldData) {
        self.data = data
        if data.heights.isEmpty {
            meanHeight = 0
        } else {
            meanHeight = data.heights.reduce(Float(0), +) / Float(data.heights.count)
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

        let h00 = data.heights[iz0 * data.nx + ix0]
        let h10 = data.heights[iz0 * data.nx + ix0 + 1]
        let h01 = data.heights[(iz0 + 1) * data.nx + ix0]
        let h11 = data.heights[(iz0 + 1) * data.nx + ix0 + 1]

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
    private let anchor: AnchorEntity
    private let pathPositions: [SIMD3<Float>]
    private let duration: TimeInterval
    private var animationTimer: Timer?
    private var animationStartTime: TimeInterval = 0

    init(anchor: AnchorEntity, pathPositions: [SIMD3<Float>], duration: TimeInterval) {
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

// MARK: - RealityKit Container

struct RealityKitContainer: UIViewRepresentable {
    let bestLine: BestLineResult
    let heightfield: HeightfieldData?
    let greenWidth: Double
    let greenHeight: Double
    let onControllerReady: (SceneController) -> Void
    private let logger = Logger(subsystem: Constants.Logging.subsystem, category: "RealityKit3D")

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.cameraMode = .nonAR
        arView.environment.background = .color(Constants.Scene3D.bgColor)

        // Remove ARView's built-in gesture recognizers to prevent conflicts with our orbit controls
        for recognizer in arView.gestureRecognizers ?? [] {
            arView.removeGestureRecognizer(recognizer)
        }

        let sampler = heightfield.map { TerrainSampler($0) }
        let S = Constants.Scene3D.scaleFactor

        // Build scene
        let anchor = AnchorEntity(world: .zero)
        buildScene(on: anchor, sampler: sampler)
        arView.scene.addAnchor(anchor)

        // Lighting
        let light = DirectionalLight()
        light.light.intensity = 3000
        light.light.color = .white
        light.shadow = .init()
        light.look(at: .zero, from: SIMD3(5, 10, 5), relativeTo: nil)
        let lightAnchor = AnchorEntity(world: .zero)
        lightAnchor.addChild(light)
        arView.scene.addAnchor(lightAnchor)

        // Camera: orbit around midpoint between ball and hole
        let ballScene = SIMD3<Float>(Float(bestLine.ballXFt) * S, 0, -1 * Float(bestLine.ballZFt) * S)
        let holeScene = SIMD3<Float>(Float(bestLine.holeXFt) * S, 0, -1 * Float(bestLine.holeZFt) * S)
        var orbitCenter = (ballScene + holeScene) / 2
        if let sampler = sampler {
            let cxFt = (bestLine.ballXFt + bestLine.holeXFt) / 2
            let czFt = -1 * (bestLine.ballZFt + bestLine.holeZFt) / 2
            orbitCenter.y = sampler.sceneYAt(xFt: cxFt, zFt: czFt)
        }

        // Position camera behind ball, elevated, looking towards hole
        let puttDir: SIMD3<Float>
        if simd_length(holeScene - ballScene) > 0.001 {
            puttDir = simd_normalize(holeScene - ballScene)
        } else {
            puttDir = SIMD3(0, 0, -1)
        }
        let puttDist = simd_length(holeScene - ballScene)
        let viewDist = max(puttDist * Constants.Scene3D.viewDistanceMultiplier, Constants.Scene3D.minViewDistance)
        let camMul = Constants.Scene3D.cameraOffsetMultiplier
        let camPos = orbitCenter - puttDir * viewDist * camMul + SIMD3(0, viewDist * camMul, 0)

        let camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = Constants.Scene3D.fieldOfViewDegrees
        camera.look(at: orbitCenter, from: camPos, relativeTo: nil)
        let cameraAnchor = AnchorEntity(world: .zero)
        cameraAnchor.addChild(camera)
        arView.scene.addAnchor(cameraAnchor)

        // Initialize orbit state from camera position
        let offset = camPos - orbitCenter
        let coord = context.coordinator
        coord.arView = arView
        coord.cameraEntity = camera
        coord.orbitCenter = orbitCenter
        coord.orbitDistance = simd_length(offset)
        coord.orbitYaw = atan2(offset.x, offset.z)
        coord.orbitPitch = asin(offset.y / max(simd_length(offset), 0.001))

        // Custom gesture recognizers
        let pan = UIPanGestureRecognizer(target: coord, action: #selector(Coordinator.handlePan(_:)))
        let pinch = UIPinchGestureRecognizer(target: coord, action: #selector(Coordinator.handlePinch(_:)))
        arView.addGestureRecognizer(pan)
        arView.addGestureRecognizer(pinch)

        // Scene controller for ball animation
        let pathPositions = computePathPositions(sampler: sampler)
        let controller = SceneController(
            anchor: anchor,
            pathPositions: pathPositions,
            duration: Double(bestLine.tEndS)
        )
        coord.sceneController = controller
        DispatchQueue.main.async { onControllerReady(controller) }

        logger.info("Scene built: terrain=\(heightfield != nil), pathPoints=\(pathPositions.count)")
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator() }

    // MARK: - Build Scene

    private func buildScene(on anchor: AnchorEntity, sampler: TerrainSampler?) {
        if let sampler = sampler, let terrain = buildTerrainMesh(sampler: sampler) {
            anchor.addChild(terrain)
        } else {
            anchor.addChild(buildFlatTerrain())
        }

        if let path = buildPathRibbon(sampler: sampler) {
            anchor.addChild(path)
        }

        let ball = buildBall(sampler: sampler)
        ball.name = "ball"
        anchor.addChild(ball)

        anchor.addChild(buildFlag(sampler: sampler))
    }

    // MARK: - Flat Terrain Fallback

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

    // MARK: - Heightfield Terrain Mesh

    private func buildTerrainMesh(sampler: TerrainSampler) -> ModelEntity? {
        let d = sampler.data
        let S = Constants.Scene3D.scaleFactor
        let H = Constants.Scene3D.heightExaggeration

        var positions: [SIMD3<Float>] = []
        positions.reserveCapacity(d.nx * d.nz)

        for iz in 0..<d.nz {
            for ix in 0..<d.nx {
                let xFt = d.xMin + Double(ix) * d.resolution
                let zFt = d.zMin + Double(iz) * d.resolution
                let hFt = d.heights[iz * d.nx + ix] - sampler.meanHeight

                positions.append(SIMD3(
                    Float(xFt) * S,
                    hFt * S * H,
                    Float(zFt) * S
                ))
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

        var indices: [UInt32] = []
        indices.reserveCapacity((d.nx - 1) * (d.nz - 1) * 6)
        for iz in 0..<(d.nz - 1) {
            for ix in 0..<(d.nx - 1) {
                let tl = UInt32(iz * d.nx + ix)
                let tr = UInt32(iz * d.nx + ix + 1)
                let bl = UInt32((iz + 1) * d.nx + ix)
                let br = UInt32((iz + 1) * d.nx + ix + 1)
                indices.append(contentsOf: [tl, bl, tr, tr, bl, br])
            }
        }

        var desc = MeshDescriptor(name: "terrain")
        desc.positions = MeshBuffers.Positions(positions)
        desc.normals = MeshBuffers.Normals(normals)
        desc.primitives = .triangles(indices)

        guard let mesh = try? MeshResource.generate(from: [desc]) else {
            logger.error("Failed to generate terrain mesh")
            return nil
        }

        var mat = SimpleMaterial()
        mat.color = .init(tint: Constants.Scene3D.greenColor)
        return ModelEntity(mesh: mesh, materials: [mat])
    }

    // MARK: - Path Ribbon

    private func buildPathRibbon(sampler: TerrainSampler?) -> ModelEntity? {
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
            let zFt = -1 * bestLine.pathZFt[i]
            let sceneX = Float(xFt) * S
            let sceneZ = Float(zFt) * S
            let sceneY: Float = sampler.map { $0.sceneYAt(xFt: xFt, zFt: zFt) + Constants.Scene3D.pathOffset }
                ?? Constants.Scene3D.pathOffset

            // Tangent direction along path (feet, but only need direction)
            let dx: Double
            let dz: Double
            if i == 0 {
                dx = bestLine.pathXFt[1] - bestLine.pathXFt[0]
                dz = bestLine.pathZFt[1] - (-1 * bestLine.pathZFt[0])
            } else if i == count - 1 {
                dx = bestLine.pathXFt[i] - bestLine.pathXFt[i - 1]
                dz = bestLine.pathZFt[i] - (-1 * bestLine.pathZFt[i - 1])
            } else {
                dx = bestLine.pathXFt[i + 1] - bestLine.pathXFt[i - 1]
                dz = bestLine.pathZFt[i + 1] - (-1 * bestLine.pathZFt[i - 1])
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

    // MARK: - Ball

    private func buildBall(sampler: TerrainSampler?) -> ModelEntity {
        let S = Constants.Scene3D.scaleFactor
        let mesh = MeshResource.generateSphere(radius: Constants.Scene3D.ballRadius)
        var mat = SimpleMaterial()
        mat.color = .init(tint: .white)
        mat.metallic = .float(0.1)
        mat.roughness = .float(0.3)

        let ball = ModelEntity(mesh: mesh, materials: [mat])
        let xFt = bestLine.ballXFt
        let zFt = -1 * bestLine.ballZFt
        let y: Float = sampler.map { $0.sceneYAt(xFt: xFt, zFt: zFt) + Constants.Scene3D.ballRadius }
            ?? Constants.Scene3D.ballRadius
        ball.position = SIMD3(Float(xFt) * S, y, Float(zFt) * S)
        logger.info("Ball placed at feet(\(xFt), \(zFt)), hole at feet(\(bestLine.holeXFt), \(bestLine.holeZFt))")
        return ball
    }

    // MARK: - Flag

    private func buildFlag(sampler: TerrainSampler?) -> Entity {
        let S = Constants.Scene3D.scaleFactor
        let root = Entity()

        let xFt = bestLine.holeXFt
        let zFt = -1 * bestLine.holeZFt
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

        root.position = SIMD3(Float(xFt) * S, baseY, Float(zFt) * S)
        return root
    }

    // MARK: - Pre-compute Path Positions

    private func computePathPositions(sampler: TerrainSampler?) -> [SIMD3<Float>] {
        let S = Constants.Scene3D.scaleFactor
        return (0..<bestLine.pathXFt.count).map { i in
            let xFt = bestLine.pathXFt[i]
            let zFt = -1 * bestLine.pathZFt[i]
            let y: Float = sampler.map { $0.sceneYAt(xFt: xFt, zFt: zFt) + Constants.Scene3D.ballRadius }
                ?? Constants.Scene3D.ballRadius
            return SIMD3(Float(xFt) * S, y, Float(zFt) * S)
        }
    }

    // MARK: - Coordinator

    class Coordinator {
        weak var arView: ARView?
        var cameraEntity: PerspectiveCamera?
        var sceneController: SceneController?
        var orbitCenter: SIMD3<Float> = .zero
        var orbitDistance: Float = 15
        var orbitYaw: Float = 0
        var orbitPitch: Float = 0.5
        private var lastPinchScale: CGFloat = 1.0

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let view = arView else { return }
            if gesture.state == .changed {
                let t = gesture.translation(in: view)
                orbitYaw += Float(t.x) * Constants.Scene3D.panSensitivity
                orbitPitch = max(Constants.Scene3D.minPitch, min(Constants.Scene3D.maxPitch, orbitPitch - Float(t.y) * Constants.Scene3D.panSensitivity))
                gesture.setTranslation(.zero, in: view)
                updateCamera()
            }
        }

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            switch gesture.state {
            case .began:
                lastPinchScale = gesture.scale
            case .changed:
                let delta = Float(gesture.scale / lastPinchScale)
                orbitDistance = max(Constants.Scene3D.minOrbitDistance, min(Constants.Scene3D.maxOrbitDistance, orbitDistance / delta))
                lastPinchScale = gesture.scale
                updateCamera()
            default:
                break
            }
        }

        func updateCamera() {
            guard let camera = cameraEntity else { return }
            let x = orbitCenter.x + orbitDistance * cos(orbitPitch) * sin(orbitYaw)
            let y = orbitCenter.y + orbitDistance * sin(orbitPitch)
            let z = orbitCenter.z + orbitDistance * cos(orbitPitch) * cos(orbitYaw)
            camera.look(at: orbitCenter, from: SIMD3(x, y, z), relativeTo: nil)
        }
    }
}

// MARK: - Preview

#Preview {
    Putt3DView(
        bestLine: BestLineResult(
            ballXFt: -10, ballZFt: 5,
            holeXFt: 0, holeZFt: 0,
            stimpFt: 10, aimOffsetDeg: 5.2,
            speedFps: 8.5, v0XFps: 6.0, v0ZFps: 6.0,
            holed: true, missFt: 0.0, tEndS: 3.5,
            pathXFt: [-10, -8, -6, -4, -2, 0],
            pathZFt: [5, 4, 3, 2, 1, 0],
            pathYFt: [0.1, 0.08, 0.06, 0.04, 0.02, 0]
        ),
        hole: Hole(
            courseId: "test",
            holeNum: 1,
            greenWidthFt: 100,
            greenHeightFt: 80,
            hasSource: true,
            hasProcessed: true,
            sourceUrls: nil,
            processedUrls: nil
        ),
        onDismiss: {}
    )
}
