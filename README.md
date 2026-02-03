# GreenReader

A golf green reading application that computes optimal putt lines using physics simulation and displays them in both 2D and 3D visualizations.

## Overview

GreenReader helps golfers read greens by:
1. Processing contour maps of golf greens into 3D heightfields
2. Simulating ball physics to find the optimal putt line for any ball/hole position
3. Displaying results on an interactive 2D map and immersive 3D Unity visualization

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              Frontend                                    │
│  React + TypeScript + Tailwind + Unity WebGL                            │
│  - Interactive green map with ball/flag placement                       │
│  - Best line visualization with path overlay                            │
│  - 3D Unity simulation with animated ball roll                          │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                           AWS Infrastructure                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐    │
│  │ CloudFront  │  │ API Gateway │  │   Lambda    │  │  DynamoDB   │    │
│  │ (Frontend)  │  │   (REST)    │  │  (Python)   │  │  (Catalog)  │    │
│  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘    │
│  ┌─────────────┐  ┌─────────────┐                                       │
│  │ CloudFront  │  │     S3      │                                       │
│  │   (CDN)     │  │   (Data)    │                                       │
│  └─────────────┘  └─────────────┘                                       │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         Backend Processing                               │
│  Python CLI for:                                                         │
│  - Interactive boundary/contour tracing from green images               │
│  - Heightfield reconstruction via RBF interpolation                     │
│  - Ball roll physics simulation with Stimpmeter calibration             │
│  - Course data upload to AWS                                            │
└─────────────────────────────────────────────────────────────────────────┘
```

## Project Structure

```
GreenReader/
├── frontend/           # React frontend with Unity WebGL viewer
│   ├── src/
│   │   ├── components/ # GreenCanvas, UnityViewer, UI components
│   │   └── lib/        # API client, types
│   └── public/unity/   # Unity WebGL build output
├── backend/            # Python processing pipeline and physics
│   ├── cli.py          # Build and upload commands
│   ├── maps/           # Geospatial transforms (lat/lon to feet)
│   ├── terrain/        # Heightfield reconstruction from contours
│   ├── physics/        # Ball roll simulation, best-line optimization
│   └── tools/          # Interactive tracing tools
├── infra/              # AWS CDK infrastructure (TypeScript)
│   └── lib/            # Stack constructs (API, storage, CDN, frontend)
└── lambdas/            # Lambda function handlers
    ├── handlers/       # Individual function code
    └── layer/          # Shared utilities (db, s3, logging)
```

## Quick Start

### Prerequisites

- Node.js 20+
- Python 3.11+
- AWS CLI configured
- AWS CDK installed (`npm install -g aws-cdk`)

### Deploy Infrastructure

```bash
cd infra
npm install
npx cdk deploy
```

### Process a New Hole

```bash
# 1. Trace boundary and contours interactively
python -m backend.tools.trace_boundary PresidioGC Hole_1
python -m backend.tools.trace_contours PresidioGC Hole_1

# 2. Build heightfield
python -m backend.cli build PresidioGC Hole_1

# 3. Upload to AWS
python -m backend.cli upload PresidioGC --course-id presidio-gc --api-url $API_URL
```

### Deploy Frontend

```bash
cd frontend
VITE_API_URL=https://your-api.execute-api.us-west-2.amazonaws.com/prod npm run build
aws s3 sync dist s3://greenreader-frontend --delete
```

## Key Features

- **Physics-based putt simulation**: Uses Stimpmeter-calibrated ball roll physics with terrain gradient forces
- **Async job processing**: Long-running bestline computations run asynchronously with DynamoDB job tracking
- **3D visualization**: Unity WebGL integration for immersive ball roll playback
- **Serverless architecture**: Fully serverless on AWS with pay-per-use pricing
- **CloudWatch observability**: JSON-structured logging with X-Ray tracing

## Documentation

- [Infrastructure README](infra/README.md) - AWS architecture, API reference, deployment
- [Backend README](backend/README.md) - Processing pipeline, CLI usage, coordinate system
