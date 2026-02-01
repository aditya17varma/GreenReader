# GreenReader Frontend

React single-page app for visualizing golf green contour data, placing ball/flag positions, and computing optimal putt lines via the GreenReader Lambda API.

## Tech Stack

- **Vite** — build tooling and dev server
- **React + TypeScript**
- **Tailwind CSS** — utility-first styling
- **shadcn/ui** — Select, Button, Card, Slider, Label components

## Setup

```bash
cd frontend
npm install
```

Create a `.env` file (or update the existing one) with your API Gateway endpoint:

```
VITE_API_URL=https://xxx.execute-api.us-west-2.amazonaws.com/prod
```

## Development

```bash
npm run dev
```

## Production Build

```bash
npm run build
npm run preview   # preview the production build locally
```

## Project Structure

```
src/
  main.tsx                        Entry point
  App.tsx                         Layout: sidebar controls + main canvas area
  index.css                       Tailwind + shadcn theme variables
  lib/
    api.ts                        Typed fetch wrappers for all API endpoints
    types.ts                      TypeScript interfaces (Course, Hole, BestLine, etc.)
    coordinates.ts                Pixel-to-feet and feet-to-pixel conversion
    utils.ts                      cn() helper for class merging
  components/
    CourseSelector.tsx             Course and hole dropdown selectors
    GreenCanvas.tsx               Green image with canvas overlay for markers and path
    PlacementToggle.tsx           "Place Flag" / "Place Ball" mode toggle
    BestLineResult.tsx            Result stats card (aim offset, speed, holed, etc.)
    ui/                           shadcn generated components
```

## UI Flow

1. **Select a course** from the dropdown (populated from `GET /courses`)
2. **Select a hole** (populated from `GET /courses/{id}`)
3. The green image loads from the CloudFront CDN (`sourceUrls["image.png"]`)
4. **Place Flag** — click the image to set the flag/hole position
5. **Place Ball** — toggle mode and click to set the ball position
6. Adjust the **Stimp slider** (default 10.0 ft, range 6–15)
7. Click **Compute Best Line** — calls `POST /courses/{id}/holes/{num}/bestline`
8. The optimal putt path draws on the canvas overlay, and result stats appear in the sidebar

## Coordinate System

The green image uses a centered coordinate system where (0, 0) is the image center:

- **x** increases to the right (feet)
- **z** increases upward (feet)
- Image pixel y-axis is flipped relative to z

Conversion formulas (from `lib/coordinates.ts`):

```
Pixel → Feet:
  x_ft = (px / displayWidth  - 0.5) * greenWidthFt
  z_ft = (0.5 - py / displayHeight) * greenHeightFt

Feet → Pixel:
  px = (x_ft / greenWidthFt  + 0.5) * displayWidth
  py = (0.5 - z_ft / greenHeightFt) * displayHeight
```

`greenWidthFt` and `greenHeightFt` come from the `GET /courses/{id}/holes/{num}` response.

## API Endpoints Used

| Method | Path | Description |
|--------|------|-------------|
| GET | `/courses` | List all courses |
| GET | `/courses/{id}` | Get course detail with hole list |
| GET | `/courses/{id}/holes/{num}` | Get hole detail (dimensions, image URLs) |
| POST | `/courses/{id}/holes/{num}/bestline` | Compute optimal putt line |

### Bestline Request Body

```json
{
  "ballXFt": 5.0,
  "ballZFt": -3.2,
  "holeXFt": 0.0,
  "holeZFt": 1.5,
  "stimpFt": 10.0
}
```

### Bestline Response

```json
{
  "bestLine": {
    "aimOffsetDeg": -2.3,
    "speedFps": 4.12,
    "holed": true,
    "missFt": 0.0,
    "tEndS": 3.45,
    "pathXFt": [5.0, 4.8, ...],
    "pathZFt": [-3.2, -2.9, ...],
    "pathYFt": [0.12, 0.11, ...]
  }
}
```
