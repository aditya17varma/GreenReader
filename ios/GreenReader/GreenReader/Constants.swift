import Foundation
import UIKit

enum Constants {
    // MARK: - API Configuration
    enum API {
        static let baseURL = "https://48gzd2bzfa.execute-api.us-west-2.amazonaws.com/prod"
    }

    // MARK: - Polling Configuration
    enum Polling {
        static let intervalSeconds: Double = 2.0
        static let timeoutSeconds: Double = 120.0
        static var maxAttempts: Int { Int(timeoutSeconds / intervalSeconds) }
        static var intervalNanoseconds: UInt64 { UInt64(intervalSeconds * 1_000_000_000) }
        static let logEveryNAttempts = 5
    }

    // MARK: - Physics Defaults
    enum Physics {
        static let defaultStimpFt: Double = 10.0
        static let defaultBallPositionFt = CGPoint(x: -10, y: 5)
        static let defaultFlagPositionFt = CGPoint(x: 0, y: 0)
    }

    // MARK: - UI Configuration
    enum UI {
        static let ballDiameter: CGFloat = 10
        static let pathLineWidth: CGFloat = 4
    }

    // MARK: - 3D Scene Configuration
    enum Scene3D {
        // Scale & terrain
        static let scaleFactor: Float = 0.5
        static let heightExaggeration: Float = 3.0

        // Ball
        static let ballRadius: Float = 0.1

        // Path ribbon
        static let pathWidth: Float = 0.1
        static let pathOffset: Float = 0.03

        // Flag
        static let poleHeight: Float = 1.5
        static let poleDiameter: Float = 0.04
        static let clothWidth: Float = 0.5
        static let clothHeight: Float = 0.3
        static let holeDiscSize: Float = 0.22

        // Colors
        static let greenColor = UIColor(red: 0.15, green: 0.5, blue: 0.15, alpha: 1.0)
        static let groundColor = UIColor(red: 0.55, green: 0.45, blue: 0.30, alpha: 1.0)
        static let bgColor = UIColor(red: 0.1, green: 0.15, blue: 0.1, alpha: 1.0)

        // Camera
        static let fieldOfViewDegrees: Float = 50
        static let viewDistanceMultiplier: Float = 1.5
        static let minViewDistance: Float = 10.0
        static let cameraOffsetMultiplier: Float = 0.5
        static let minOrbitDistance: Float = 2
        static let maxOrbitDistance: Float = 50
        static let panSensitivity: Float = 0.005
        static let minPitch: Float = 0.05
        static var maxPitch: Float { .pi / 2 - 0.05 }

        // AR
        static let arTargetWidthM: Float = 0.5
        static let arMinScale: Float = 0.1
        static let arMaxScale: Float = 5.0
    }

    // MARK: - Logging
    enum Logging {
        static let subsystem = "com.greenreader"
    }
}
