import SwiftUI
import os.log

struct GreenView: View {
    let courseId: String
    let holeNum: Int

    private let logger = Logger(subsystem: Constants.Logging.subsystem, category: "GreenView")

    @State private var hole: Hole?
    @State private var mapImage: UIImage?
    @State private var isLoading = true
    @State private var errorMessage: String?

    // Ball and flag positions in feet (relative to green center)
    @State private var ballPositionFt: CGPoint = Constants.Physics.defaultBallPositionFt
    @State private var flagPositionFt: CGPoint = Constants.Physics.defaultFlagPositionFt

    // Best line result
    @State private var bestLine: BestLineResult?
    @State private var isComputing = false
    @State private var computeError: String?
    @State private var show3DView = false

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                Spacer()
                ProgressView("Loading hole...")
                Spacer()
            } else if let error = errorMessage {
                Spacer()
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text(error)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        Task { await loadHole() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                Spacer()
            } else if let hole = hole, let image = mapImage {
                // Green dimensions
                let greenWidth = hole.greenWidthFt ?? 100
                let greenHeight = hole.greenHeightFt ?? 80

                GeometryReader { geo in
                    let availableHeight = geo.size.height
                    let availableWidth = geo.size.width
                    let scale = min(availableWidth / greenWidth, availableHeight / greenHeight)
                    let imageSize = CGSize(width: greenWidth * scale, height: greenHeight * scale)

                    ZStack {
                        // Map image
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: imageSize.width, height: imageSize.height)

                        // Best line path
                        if let bestLine = bestLine {
                            PathShape(bestLine: bestLine, greenWidth: greenWidth, greenHeight: greenHeight)
                                .stroke(Color.blue, lineWidth: Constants.UI.pathLineWidth)
                                .frame(width: imageSize.width, height: imageSize.height)
                        }

                        // Flag (draggable)
                        Image(systemName: "flag.fill")
                            .foregroundColor(.red)
                            .font(.title)
                            .position(feetToPixel(flagPositionFt, greenWidth: greenWidth, greenHeight: greenHeight, size: imageSize))
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        flagPositionFt = pixelToFeet(value.location, greenWidth: greenWidth, greenHeight: greenHeight, size: imageSize)
                                        bestLine = nil
                                    }
                            )

                        // Ball (draggable)
                        Circle()
                            .fill(Color.white)
                            .frame(width: Constants.UI.ballDiameter, height: Constants.UI.ballDiameter)
                            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 2)
                            .overlay(
                                Circle()
                                    .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                            )
                            .position(feetToPixel(ballPositionFt, greenWidth: greenWidth, greenHeight: greenHeight, size: imageSize))
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        ballPositionFt = pixelToFeet(value.location, greenWidth: greenWidth, greenHeight: greenHeight, size: imageSize)
                                        bestLine = nil
                                    }
                            )
                    }
                    .frame(width: imageSize.width, height: imageSize.height)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }

                // Bottom panel
                VStack(spacing: 12) {
                    // Result info
                    if let bestLine = bestLine {
                        HStack(spacing: 20) {
                            VStack {
                                Text("Aim")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("\(abs(bestLine.aimOffsetDeg), specifier: "%.1f")°")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                Text(bestLine.aimOffsetDeg > 0 ? "left" : "right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Divider()
                                .frame(height: 50)

                            VStack {
                                Text("Speed")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("\(bestLine.speedFps, specifier: "%.1f")")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                Text("ft/s")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Divider()
                                .frame(height: 50)

                            VStack {
                                Text("Result")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                if bestLine.holed {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(.green)
                                    Text("Holed!")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                } else {
                                    Text("\(bestLine.missFt, specifier: "%.1f") ft")
                                        .font(.title2)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.orange)
                                    Text("miss")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(12)
                        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                    }

                    // Error message
                    if let error = computeError {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                    }

                    // Buttons row
                    HStack(spacing: 12) {
                        // Compute button
                        Button(action: computeBestLine) {
                            HStack {
                                if isComputing {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                } else {
                                    Image(systemName: "line.diagonal.arrow")
                                }
                                Text(isComputing ? "Computing..." : "Compute")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(isComputing ? Color.gray : Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .disabled(isComputing)

                        // View 3D button (only enabled when bestLine exists)
                        Button(action: { show3DView = true }) {
                            HStack {
                                Image(systemName: "cube")
                                Text("View 3D")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(bestLine != nil ? Color.green : Color.gray)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .disabled(bestLine == nil)
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
            }
        }
        .navigationTitle("Hole \(holeNum)")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadHole()
        }
        .fullScreenCover(isPresented: $show3DView) {
            if let bestLine = bestLine, let hole = hole {
                Putt3DView(
                    bestLine: bestLine,
                    hole: hole,
                    onDismiss: { show3DView = false }
                )
            }
        }
    }

    // MARK: - Coordinate Conversion

    private func feetToPixel(_ ft: CGPoint, greenWidth: Double, greenHeight: Double, size: CGSize) -> CGPoint {
        // Feet: origin at center, +X = right, +Z = up
        // Pixels: origin at top-left, +X = right, +Y = down
        let px = (ft.x / greenWidth + 0.5) * size.width
        let py = (0.5 - ft.y / greenHeight) * size.height
        return CGPoint(x: px, y: py)
    }

    private func pixelToFeet(_ px: CGPoint, greenWidth: Double, greenHeight: Double, size: CGSize) -> CGPoint {
        let fx = (px.x / size.width - 0.5) * greenWidth
        let fz = (0.5 - px.y / size.height) * greenHeight
        return CGPoint(x: fx, y: fz)
    }

    // MARK: - Data Loading

    private func loadHole() async {
        isLoading = true
        errorMessage = nil

        do {
            hole = try await GreenReaderAPI.shared.getHole(courseId: courseId, holeNum: holeNum)

            // Load map image
            if let urlString = hole?.sourceUrls?.map, let url = URL(string: urlString) {
                let (data, _) = try await URLSession.shared.data(from: url)
                mapImage = UIImage(data: data)
            } else {
                errorMessage = "No map image available"
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func computeBestLine() {
        isComputing = true
        bestLine = nil
        computeError = nil

        Task {
            do {
                logger.info("Computing best line: ball=(\(ballPositionFt.x), \(ballPositionFt.y)), hole=(\(flagPositionFt.x), \(flagPositionFt.y))")

                let request = BestLineRequest(
                    ballXFt: ballPositionFt.x,
                    ballZFt: ballPositionFt.y,
                    holeXFt: flagPositionFt.x,
                    holeZFt: flagPositionFt.y,
                    stimpFt: Constants.Physics.defaultStimpFt
                )

                // Submit job - may return cached result or job ID
                let submitResult = try await GreenReaderAPI.shared.submitBestLine(
                    courseId: courseId,
                    holeNum: holeNum,
                    request: request
                )

                switch submitResult {
                case .cached(let result):
                    // Cache hit - we already have the result
                    logger.info("Got cached result: holed=\(result.holed)")
                    bestLine = result

                case .job(let jobId, let status):
                    // New job - need to poll for result
                    logger.info("Job submitted: \(jobId), status=\(status)")
                    bestLine = try await GreenReaderAPI.shared.waitForBestLine(
                        courseId: courseId,
                        holeNum: holeNum,
                        jobId: jobId
                    )
                }

                logger.info("Best line computed successfully")
            } catch {
                logger.error("Error computing best line: \(error.localizedDescription)")
                computeError = error.localizedDescription
            }

            isComputing = false
        }
    }
}

// MARK: - Path Shape

struct PathShape: Shape {
    let bestLine: BestLineResult
    let greenWidth: Double
    let greenHeight: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()

        guard !bestLine.pathXFt.isEmpty else { return path }

        let firstPoint = feetToPixel(
            x: bestLine.pathXFt[0],
            z: bestLine.pathZFt[0],
            rect: rect
        )
        path.move(to: firstPoint)

        for i in 1..<bestLine.pathXFt.count {
            let point = feetToPixel(
                x: bestLine.pathXFt[i],
                z: bestLine.pathZFt[i],
                rect: rect
            )
            path.addLine(to: point)
        }

        return path
    }

    private func feetToPixel(x: Double, z: Double, rect: CGRect) -> CGPoint {
        let px = (x / greenWidth + 0.5) * rect.width
        let py = (0.5 - z / greenHeight) * rect.height
        return CGPoint(x: px, y: py)
    }
}

#Preview {
    NavigationStack {
        GreenView(courseId: "presidio-gc", holeNum: 1)
    }
}
