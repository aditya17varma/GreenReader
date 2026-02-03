# GreenReader Backend

Processes golf green contour maps into 3D heightfields and uploads them to AWS.

## Workflow

There are three stages to processing a new hole:

### Stage 1 -- Prepare Input Files

For each hole, create a folder under `resources/greenMaps/<Course>/<Hole_N>/` containing:

| File | Description |
|------|-------------|
| `config.json` | Real-world lat/lon extents (N/S/E/W) and contour interval |
| `Hole_N_contour.png` | Contour map image of the green (used for tracing) |
| `Hole_N_map.png` | Google Maps screenshot of the green (displayed in frontend) |

`config.json` format:

```json
{
  "extents": {
    "north": { "lat": 37.790176, "lon": -122.465818 },
    "south": { "lat": 37.789957, "lon": -122.465906 },
    "east":  { "lat": 37.790054, "lon": -122.465659 },
    "west":  { "lat": 37.790039, "lon": -122.466013 }
  },
  "contour_interval_ft": 0.25
}
```

### Stage 2 -- Trace Boundary and Contours (Interactive)

Run the interactive tracing tools to manually outline the green and its elevation contours. These open a matplotlib GUI where you click to place points on the image.

```bash
# Trace the green boundary
python -m backend.tools.trace_boundary PresidioGC Hole_1

# Trace elevation contour lines
python -m backend.tools.trace_contours PresidioGC Hole_1
```

**trace_boundary controls:**
- Left click: add boundary point
- Backspace: undo last point
- Enter: save and exit

**trace_contours controls:**
- Left click: add point to current contour
- Backspace: undo last point
- `n`: finish current contour, move to next level (k+1)
- `p`: finish current contour, move to previous level (k-1)
- `c`: clear current contour
- `s`: save all contours to JSON
- `q`: quit

This produces `Hole_N_boundary.json` and `Hole_N_contours.json` in the hole folder.

### Stage 3 -- Build Heightfield

Reconstruct the 3D heightfield from boundary + contours using RBF (thin-plate spline) interpolation:

```bash
# Build all holes for a course
python -m backend.cli build PresidioGC

# Build a single hole
python -m backend.cli build PresidioGC Hole_1
```

Output goes to `Hole_N/unity/`:
- `Hole_N_heightfield.bin` -- float32 elevation grid (row-major, shape nz x nx)
- `Hole_N_heightfield.json` -- grid metadata (dimensions, resolution, origin)

### Stage 4 -- Upload to AWS

Upload source and processed files to the GreenReader API / S3:

```bash
# Upload all holes
python -m backend.cli upload PresidioGC \
    --course-id presidio-gc \
    --api-url https://xxx.execute-api.us-west-2.amazonaws.com/prod

# Upload a single hole
python -m backend.cli upload PresidioGC \
    --course-id presidio-gc \
    --api-url https://xxx.execute-api.us-west-2.amazonaws.com/prod \
    --hole Hole_1
```

The `--api-url` can also be set via the `GREENREADER_API_URL` environment variable.

The upload flow per hole:
1. Registers the hole via `POST /courses/{courseId}/holes/{holeNum}` to get pre-signed S3 upload URLs
2. Uploads source files (image, boundary, contours) and processed files (heightfield)
3. Updates the hole status flags (`hasSource`, `hasProcessed`)

## Folder Structure

```
backend/
  cli.py                  # CLI entry point (build, upload)
  __main__.py             # Alias so `python -m backend` works
  maps/                   # Geospatial: lat/lon to feet, pixel transforms
  terrain/                # Heightfield reconstruction from contours (RBF)
  physics/                # Ball roll simulation, best-line computation
  tools/
    paths.py              # Centralized path resolution for all tools
    trace_boundary.py     # Interactive boundary tracing (matplotlib)
    trace_contours.py     # Interactive contour tracing (matplotlib)
    export_heightfield_for_unity.py  # Standalone heightfield export
  resources/
    greenMaps/
      PresidioGC/
        Hole_1/
          config.json               # Input: lat/lon extents
          Hole_1_contour.png        # Input: contour map image (for tracing)
          Hole_1_map.png            # Input: Google Maps image (for frontend)
          Hole_1_boundary.json      # Stage 2 output: boundary polygon
          Hole_1_contours.json      # Stage 2 output: traced contours
          unity/
            Hole_1_heightfield.json # Stage 3 output: grid metadata
            Hole_1_heightfield.bin  # Stage 3 output: elevation data
```

## Coordinate System

- **X** (feet): east/west, +X = east
- **Z** (feet): north/south, +Z = north
- **Y** (feet): elevation
- Origin: center of green (0, 0)

## Heightfield Output Format

`Hole_N_heightfield.json`:
```json
{
  "units": { "x": "ft", "z": "ft", "y": "ft" },
  "grid": {
    "nx": 206,
    "nz": 169,
    "resolution_ft": 0.5,
    "x_min_ft": -51.22,
    "z_min_ft": -41.85
  }
}
```

`Hole_N_heightfield.bin`: raw float32 array, row-major order, shape `(nz, nx)`. Values are elevation in feet; 0.0 outside the green boundary.

## S3 Key Layout

When uploaded, files are stored as:
```
{courseId}/{holeNum}/source/contour.png
{courseId}/{holeNum}/source/map.png
{courseId}/{holeNum}/source/boundary.json
{courseId}/{holeNum}/source/contours.json
{courseId}/{holeNum}/processed/heightfield.json
{courseId}/{holeNum}/processed/heightfield.bin
```

## Dependencies

Core: `numpy`, `scipy`, `shapely`, `pyproj`, `opencv-python`, `matplotlib`

Upload: `requests`

Install: `pip install -r requirements.txt`
