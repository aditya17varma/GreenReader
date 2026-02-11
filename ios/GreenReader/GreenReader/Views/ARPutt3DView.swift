import SwiftUI
import RealityKit
import ARKit
import os

// MARK: - PuttARView

struct PuttARView: View {
    let bestLine: BestLineResult
    let hole: Hole
    let onDismiss: () -> Void

    @State private var isLoading = true
    @State private var heightfieldData: HeightfieldData?
    @State private var boundaryData: [BoundaryPoint]?
    @State private var sceneController: SceneController?
    @State private var isPlaced = false
    private let logger = Logger(subsystem: Constants.Logging.subsystem, category: "PuttARView")

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
                ARKitContainer(
                    bestLine: bestLine,
                    heightfield: heightfieldData,
                    boundary: boundaryData,
                    greenWidth: hole.greenWidthFt ?? 100,
                    greenHeight: hole.greenHeightFt ?? 80,
                    onControllerReady: { sceneController = $0 },
                    onPlaced: { isPlaced = true }
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

                if !isLoading && !isPlaced {
                    Text("Tap a surface to place the green")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                        .padding(.bottom, 40)
                }

                if isPlaced {
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

// MARK: - ARKit Container

struct ARKitContainer: UIViewRepresentable {
    let bestLine: BestLineResult
    let heightfield: HeightfieldData?
    let boundary: [BoundaryPoint]?
    let greenWidth: Double
    let greenHeight: Double
    let onControllerReady: (SceneController) -> Void
    let onPlaced: () -> Void
    private let logger = Logger(subsystem: Constants.Logging.subsystem, category: "ARKit3D")

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)

        // Configure AR session with horizontal plane detection
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        config.environmentTexturing = .automatic
        arView.session.run(config)

        // Coaching overlay to guide the user
        let coaching = ARCoachingOverlayView()
        coaching.goal = .horizontalPlane
        coaching.session = arView.session
        coaching.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        arView.addSubview(coaching)

        // Store references in coordinator
        let coord = context.coordinator
        coord.arView = arView
        coord.bestLine = bestLine
        coord.heightfield = heightfield
        coord.boundary = boundary
        coord.greenWidth = greenWidth
        coord.greenHeight = greenHeight
        coord.onControllerReady = onControllerReady
        coord.onPlaced = onPlaced
        coord.logger = logger

        // Tap to place
        let tap = UITapGestureRecognizer(target: coord, action: #selector(Coordinator.handleTap(_:)))
        arView.addGestureRecognizer(tap)

        // Pinch to scale (after placement)
        let pinch = UIPinchGestureRecognizer(target: coord, action: #selector(Coordinator.handlePinch(_:)))
        arView.addGestureRecognizer(pinch)

        // Rotate gesture (after placement)
        let rotation = UIRotationGestureRecognizer(target: coord, action: #selector(Coordinator.handleRotation(_:)))
        arView.addGestureRecognizer(rotation)

        // Allow simultaneous gestures
        pinch.delegate = coord
        rotation.delegate = coord

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator() }

    // MARK: - Coordinator

    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var arView: ARView?
        var bestLine: BestLineResult?
        var heightfield: HeightfieldData?
        var boundary: [BoundaryPoint]?
        var greenWidth: Double = 100
        var greenHeight: Double = 80
        var onControllerReady: ((SceneController) -> Void)?
        var onPlaced: (() -> Void)?
        var logger: Logger?

        private var greenEntity: Entity?
        private var isPlaced = false
        private var lastPinchScale: CGFloat = 1.0
        private var currentScale: Float = 1.0

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            true
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard !isPlaced,
                  let arView = arView,
                  let bestLine = bestLine else { return }

            let location = gesture.location(in: arView)
            let results = arView.raycast(from: location, allowing: .estimatedPlane, alignment: .horizontal)

            guard let first = results.first else {
                logger?.info("No plane detected at tap location")
                return
            }

            // Create anchor at the raycast hit
            let anchor = AnchorEntity(raycastResult: first)

            // Build scene inside a container entity for scaling/rotating
            let container = Entity()
            let builder = GreenSceneBuilder(
                bestLine: bestLine,
                heightfield: heightfield,
                boundary: boundary,
                greenWidth: greenWidth,
                greenHeight: greenHeight
            )
            builder.buildScene(on: container)

            // Add directional light as child so it moves with the green
            let light = DirectionalLight()
            light.light.intensity = 2000
            light.light.color = .white
            light.shadow = .init()
            light.look(at: .zero, from: SIMD3(5, 10, 5), relativeTo: nil)
            container.addChild(light)

            // Scale to fit on a surface: target ~0.5m wide
            let greenSceneWidth = Float(greenWidth) * Constants.Scene3D.scaleFactor
            let arScale = Constants.Scene3D.arTargetWidthM / greenSceneWidth
            container.scale = SIMD3(repeating: arScale)
            currentScale = arScale

            anchor.addChild(container)
            arView.scene.addAnchor(anchor)
            greenEntity = container

            isPlaced = true
            logger?.info("Green placed in AR, scale=\(arScale)")

            // Set up animation controller
            let pathPositions = builder.computePathPositions()
            let controller = SceneController(
                anchor: container,
                pathPositions: pathPositions,
                duration: Double(bestLine.tEndS)
            )

            DispatchQueue.main.async { [self] in
                onControllerReady?(controller)
                onPlaced?()
            }
        }

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard isPlaced, let entity = greenEntity else { return }

            switch gesture.state {
            case .began:
                lastPinchScale = gesture.scale
            case .changed:
                let delta = Float(gesture.scale / lastPinchScale)
                currentScale = max(
                    currentScale * Constants.Scene3D.arMinScale,
                    min(currentScale * Constants.Scene3D.arMaxScale, currentScale * delta)
                )
                entity.scale = SIMD3(repeating: currentScale)
                lastPinchScale = gesture.scale
            default:
                break
            }
        }

        @objc func handleRotation(_ gesture: UIRotationGestureRecognizer) {
            guard isPlaced, let entity = greenEntity else { return }

            if gesture.state == .changed {
                entity.orientation *= simd_quatf(angle: Float(-gesture.rotation), axis: SIMD3(0, 1, 0))
                gesture.rotation = 0
            }
        }
    }
}
