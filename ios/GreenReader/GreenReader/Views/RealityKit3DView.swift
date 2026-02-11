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
    @State private var boundaryData: [BoundaryPoint]?
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
                    boundary: boundaryData,
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

                    PuttInfoPanel(bestLine: bestLine)
                }
            }
        }
        .task { await loadHeightfield() }
    }

    private func loadHeightfield() async {
        heightfieldData = await GreenSceneBuilder.loadHeightfield(from: hole, logger: logger)
        boundaryData = await GreenSceneBuilder.loadBoundary(from: hole, logger: logger)
        isLoading = false
    }
}

// MARK: - Putt Info Panel

struct PuttInfoPanel: View {
    let bestLine: BestLineResult

    var body: some View {
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

// MARK: - RealityKit Container

struct RealityKitContainer: UIViewRepresentable {
    let bestLine: BestLineResult
    let heightfield: HeightfieldData?
    let boundary: [BoundaryPoint]?
    let greenWidth: Double
    let greenHeight: Double
    let onControllerReady: (SceneController) -> Void
    private let logger = Logger(subsystem: Constants.Logging.subsystem, category: "RealityKit3D")

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.cameraMode = .nonAR
        arView.environment.background = .color(Constants.Scene3D.bgColor)

        // Remove ARView's built-in gesture recognizers to prevent conflicts
        for recognizer in arView.gestureRecognizers ?? [] {
            arView.removeGestureRecognizer(recognizer)
        }

        let builder = GreenSceneBuilder(
            bestLine: bestLine,
            heightfield: heightfield,
            boundary: boundary,
            greenWidth: greenWidth,
            greenHeight: greenHeight
        )

        // Build scene
        let anchor = AnchorEntity(world: .zero)
        builder.buildScene(on: anchor)
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
        let orbitCenter = builder.orbitCenter()
        let ballScene = builder.ballScenePosition()
        let holeScene = builder.holeScenePosition()

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
        let pathPositions = builder.computePathPositions()
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
