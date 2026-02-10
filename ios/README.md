# GreenReader iOS App

A native SwiftUI iOS application for reading golf putting greens. The app displays interactive 2D green maps, allows positioning of ball and flag, computes optimal putting lines via a cloud API, and visualizes the putt trajectory in 3D using RealityKit.

## Features

- **Course Browser**: Browse available golf courses with hole information
- **Interactive Green Map**: View 2D green topology with draggable ball and flag markers
- **Best Line Computation**: Calculate the optimal putting line using physics simulation via AWS Lambda
- **3D Visualization**: View the computed putt trajectory in a native RealityKit 3D scene with animated ball roll

## Architecture

```
ios/GreenReader/
├── GreenReader/
│   ├── GreenReaderApp.swift       # App entry point
│   ├── ContentView.swift          # Root view
│   ├── Constants.swift            # App-wide configuration
│   ├── Models/
│   │   ├── Course.swift           # Course & CourseDetail models
│   │   ├── Hole.swift             # Hole & URL models
│   │   └── BestLine.swift         # BestLineRequest & BestLineResult
│   ├── Views/
│   │   ├── CourseListView.swift   # Course browser
│   │   ├── HoleListView.swift     # Hole selection for a course
│   │   ├── GreenView.swift        # Main green map with ball/flag
│   │   └── RealityKit3DView.swift   # 3D visualization with RealityKit (Putt3DView)
│   └── Services/
│       └── GreenReaderAPI.swift   # REST API client
└── GreenReader.xcodeproj          # Xcode project
```

## Navigation Flow

```
CourseListView → HoleListView → GreenView → Putt3DView
     │               │              │            │
     │               │              │            └── 3D ball roll simulation
     │               │              └── 2D green map, compute best line
     │               └── Select hole (1-18)
     └── Browse/select course
```

## Key Components

### Models

**Course.swift**
- `Course`: Basic course info (id, name, city, state, numHoles)
- `CourseDetail`: Full course with array of holes
- `HoleSummary`: Hole metadata (number, dimensions, processing status)

**Hole.swift**
- `Hole`: Complete hole data with source and processed URLs
- `SourceUrls`: Links to map.png, contour.png, boundary.json, contours.json
- `ProcessedUrls`: Links to heightfield.json, heightfield.bin

**BestLine.swift**
- `BestLineRequest`: Input parameters (ball position, hole position, stimp)
- `BestLineResult`: Computed result including aim offset, speed, trajectory path

### Services

**GreenReaderAPI.swift**

Singleton API client using async/await. Handles:
- `listCourses()` - GET /courses
- `getCourse(id:)` - GET /courses/{id}
- `getHole(courseId:holeNum:)` - GET /courses/{id}/holes/{num}
- `submitBestLine(...)` - POST /courses/{id}/holes/{num}/bestline
- `waitForBestLine(...)` - Poll until job completes

The best line computation uses an async job pattern:
1. Submit request → returns either cached result or job ID
2. If job ID returned, poll GET /bestline/{jobId} until complete
3. Polling configured via `Constants.Polling` (2s interval, 120s timeout)

### Views

**CourseListView.swift**
- Fetches and displays list of courses
- Navigation to HoleListView on selection

**HoleListView.swift**
- Displays holes for selected course
- Shows processing status (checkmark = ready)
- Disabled holes that haven't been processed yet

**GreenView.swift**
- Main interactive view with:
  - Green map image from S3
  - Draggable ball marker (white circle)
  - Draggable flag marker (red flag)
  - Best line path overlay (blue line)
- Bottom panel with:
  - Aim offset (degrees left/right)
  - Speed (ft/s)
  - Result (holed or miss distance)
- "Compute" button triggers API call
- "View 3D" button opens RealityKit visualization

**RealityKit3DView.swift (Putt3DView)**
- Native iOS 3D visualization using RealityKit with ARView in nonAR mode
- Features:
  - 3D terrain mesh generated from heightfield data via MeshDescriptor
  - Animated golf ball following the computed trajectory (60fps timer-based)
  - Flag and hole at target position
  - Interactive camera orbit (drag to rotate, pinch to zoom)
  - Roll/Reset controls for ball animation
  - Info panel showing aim, speed, and result
- Loads heightfield.json to create terrain topology
- Ball animation loops continuously along the path

### Constants

Centralized configuration in `Constants.swift`:

```swift
Constants.API.baseURL               // API endpoint
Constants.Polling.intervalSeconds   // 2.0
Constants.Polling.timeoutSeconds    // 120.0
Constants.Physics.defaultStimpFt    // 10.0 (green speed)
Constants.Physics.defaultBallPositionFt  // CGPoint(x: -10, y: 5)
Constants.Physics.defaultFlagPositionFt  // CGPoint(x: 0, y: 0)
Constants.UI.ballDiameter           // 24 points
Constants.UI.pathLineWidth          // 4 points
Constants.Logging.subsystem         // "com.greenreader"
```

## 3D Visualization (RealityKit)

The app uses Apple's RealityKit framework (the recommended replacement for SceneKit) for 3D visualization:

### Features
- **Terrain Mesh**: Generated from heightfield data via `MeshDescriptor` with exaggerated elevation
- **Ball Animation**: Smooth 60fps timer-based interpolation along the computed path
- **Interactive Camera**: Custom orbit camera with pan (rotate) and pinch (zoom) gestures
- **Lighting**: Directional light with shadows via `DirectionalLight`
- **PBR Materials**: Physically-based rendering with `SimpleMaterial`

### Future: ARKit Migration

RealityKit is designed for easy AR integration:
- Replace `ARView(cameraMode: .nonAR)` with `ARView(cameraMode: .ar)`
- Add `ARWorldTrackingConfiguration` for plane detection
- Place the green on real surfaces using `AnchorEntity(.plane(...))`
- All 3D content (meshes, materials, animations) transfers unchanged

## API Reference

### List Courses
```
GET /courses
Response: { "courses": [{ "id", "name", "city", "state", "numHoles" }] }
```

### Get Course
```
GET /courses/{courseId}
Response: { "course": { "id", "name", "numHoles", "holes": [...] } }
```

### Get Hole
```
GET /courses/{courseId}/holes/{holeNum}
Response: { "hole": { "courseId", "holeNum", "greenWidthFt", "greenHeightFt", "sourceUrls", "processedUrls" } }
```

### Compute Best Line
```
POST /courses/{courseId}/holes/{holeNum}/bestline
Body: { "ballXFt", "ballZFt", "holeXFt", "holeZFt", "stimpFt" }

Response (cached):
{ "bestLine": { "aimOffsetDeg", "speedFps", "holed", "missFt", "pathXFt", "pathZFt", "pathYFt", ... } }

Response (new job):
{ "jobId": "uuid", "status": "queued" }
```

### Get Job Status
```
GET /courses/{courseId}/holes/{holeNum}/bestline/{jobId}

Response (pending):
{ "jobId": "uuid", "status": "running" }

Response (complete):
{ "bestLine": { ... } }
```

## Coordinate System

- **Feet coordinates**: Origin at green center
  - +X = right
  - +Z = up (towards back of green)
- **Pixel coordinates**: Origin at top-left of image
  - +X = right
  - +Y = down

Conversion functions in `GreenView.swift`:
- `feetToPixel(_:greenWidth:greenHeight:size:)` - Feet → Pixels
- `pixelToFeet(_:greenWidth:greenHeight:size:)` - Pixels → Feet

## Requirements

- iOS 18.0+
- Xcode 16.0+
- Swift 5.9+

## Building

1. Open `ios/GreenReader/GreenReader.xcodeproj` in Xcode
2. Select target device/simulator
3. Build and run (Cmd+R)

No additional setup required - the app uses native iOS frameworks only.

## Troubleshooting

### API Timeout
The best line computation can take up to 2 minutes for complex greens. The app polls every 2 seconds with a 120-second timeout. Check network connectivity if timeouts persist.

### Hole Not Selectable
Holes appear grayed out until they have processed heightfield data. Use the admin API or web interface to process hole data first.

### 3D View Shows Flat Terrain
If the heightfield.json fails to load, the 3D view falls back to a flat green plane. Check that the hole has `processedUrls.heightfieldJson` available.

## License

See root LICENSE file.
