# GreenReader Infrastructure

AWS CDK (TypeScript) stack that deploys the GreenReader hosting layer — a serverless backend for storing golf course green contour data, computing best putt lines on demand, and serving it all to Unity/XR clients.

## Architecture

```
                          ┌──────────────┐
                          │  CloudFront  │
                          │    (CDN)     │
                          └──────┬───────┘
                                 │ Origin Access Control
                                 ▼
┌──────────────┐          ┌──────────────┐
│  API Gateway │          │      S3      │
│   (REST)     │          │  (DataBucket)│
└──────┬───────┘          └──────▲───────┘
       │ proxy                   │ read/write
       ▼                         │
┌──────────────┐          ┌──────┴───────┐
│   Lambda     │─────────►│  DynamoDB    │
│  (Python)    │          │ (CatalogTable│
└──────────────┘          └──────────────┘
```

**Upload flow** (local machine → cloud):
1. Local processing creates boundary, contour, and heightfield data
2. Client calls `POST /courses/{id}/holes/{num}` — Lambda returns pre-signed S3 upload URLs
3. Client uploads files directly to S3 using the pre-signed URLs
4. Client calls `PUT /courses/{id}/holes/{num}` to mark the hole as having source/processed data

**Download flow** (Unity client ← cloud):
1. Client calls `GET /courses` to list available courses
2. Client calls `GET /courses/{id}/holes/{num}` — Lambda returns hole metadata and CloudFront download URLs
3. Unity downloads `heightfield.json` and `heightfield.bin` directly from CloudFront

**Compute flow** (bestline calculation):
1. Client calls `POST /courses/{id}/holes/{num}/bestline` with ball position, hole/flag position, and stimp reading
2. Lambda downloads the heightfield from S3, reconstructs the terrain, and runs coarse-to-fine ball roll optimization
3. Returns the optimal launch angle, speed, and full ball path

## AWS Resources

### S3 Bucket (`StorageConstruct`)

Stores all binary and JSON artifacts for every course and hole.

**Key layout:**
```
{courseId}/{holeNum}/
  source/
    image.png              # Original green contour map image
    boundary.json          # Traced boundary polygon + hole location
    contours.json          # Traced elevation contour lines
  processed/
    heightfield.json       # Grid metadata (dimensions, resolution, origin)
    heightfield.bin        # Float32 elevation grid (row-major, little-endian)
```

**Configuration:**
- Public access fully blocked — all reads go through CloudFront (OAC) or pre-signed URLs
- CORS enabled for PUT and GET (supports browser-based uploads if needed)
- Removal policy: DESTROY (development — switch to RETAIN for production)

### DynamoDB Table (`StorageConstruct`)

Single-table design cataloging courses and holes. Pay-per-request billing.

**Schema:**

| PK | SK | Description |
|----|-----|-------------|
| `COURSE#{courseId}` | `META` | Course metadata (name, city, state, location, numHoles) |
| `COURSE#{courseId}` | `HOLE#01` | Hole metadata (greenWidthFt, greenHeightFt, holeXzFt, hasSource, hasProcessed) |

**GSI (`gsi1`)** — used for listing all courses:

| gsi1pk | gsi1sk | Item |
|--------|--------|------|
| `COURSES` | `{courseId}` | Course META items |

Query `gsi1pk = "COURSES"` returns all courses without a table scan.

### CloudFront Distribution (`CdnConstruct`)

Serves files from S3 to Unity clients worldwide.

- **Origin**: S3 bucket via Origin Access Control (OAC) — the bucket stays private, CloudFront authenticates to S3
- **Protocol**: HTTPS only (HTTP redirects to HTTPS)
- **Cache**: Uses the `CACHING_OPTIMIZED` managed policy — processed files are immutable once written, so aggressive caching is appropriate

### API Gateway + Lambda (`ApiConstruct`)

REST API with 7 Lambda functions (Python 3.12). CRUD functions share a Lambda Layer containing DynamoDB, S3, and HTTP response utilities. The compute function is bundled separately with numpy and the physics engine.

**Endpoints:**

| Method | Path | Handler | Description |
|--------|------|---------|-------------|
| `GET` | `/courses` | `list_courses` | List all courses (queries GSI) |
| `POST` | `/courses` | `create_course` | Create a course. Body: `{id, name, city?, state?, location?, numHoles?}` |
| `GET` | `/courses/{courseId}` | `get_course` | Course details + list of holes with status |
| `GET` | `/courses/{courseId}/holes/{holeNum}` | `get_hole` | Hole metadata + CloudFront download URLs for source/processed files |
| `POST` | `/courses/{courseId}/holes/{holeNum}` | `register_hole` | Register a hole, returns pre-signed S3 upload URLs |
| `PUT` | `/courses/{courseId}/holes/{holeNum}` | `update_hole` | Update hole fields (hasSource, hasProcessed, greenWidthFt, etc.) |
| `POST` | `/courses/{courseId}/holes/{holeNum}/bestline` | `compute_bestline` | Compute optimal putt line on demand (see below) |

**Bestline compute request:**
```json
{
  "ballXFt": -11.68,
  "ballZFt": 2.27,
  "holeXFt": 28.32,
  "holeZFt": -2.73,
  "stimpFt": 10.0
}
```
- `ballXFt`, `ballZFt` — required, ball position in local feet
- `holeXFt`, `holeZFt` — optional, defaults to the hole location stored in heightfield metadata
- `stimpFt` — optional, defaults to 10.0

**Bestline compute response:**
```json
{
  "bestLine": {
    "aimOffsetDeg": 16.6,
    "speedFps": 10.0,
    "v0XFps": 9.86,
    "v0ZFps": 1.65,
    "holed": true,
    "missFt": 0.176,
    "tEndS": 6.46,
    "pathXFt": [...],
    "pathZFt": [...],
    "pathYFt": [...]
  }
}
```

### Lambda Handlers

Each handler lives in `lambdas/handlers/<name>/index.py`. All handlers use JSON-structured logging (CloudWatch Logs Insights queryable) and a top-level try/except that returns 500 on unhandled errors.

Replace `$API` with your API Gateway base URL:
```bash
API=https://48gzd2bzfa.execute-api.us-west-2.amazonaws.com/prod
```

#### `list_courses` — List all courses

Returns all courses by querying the `gsi1` GSI.

```bash
curl -s "$API/courses" | python3 -m json.tool
```

Response:
```json
{
  "courses": [
    { "id": "presidio-gc", "name": "PresidioGC", "city": null, "state": null, "numHoles": 18 }
  ]
}
```

#### `create_course` — Create a course

Creates a new course record. Idempotent (overwrites if course ID already exists).

```bash
curl -s -X POST "$API/courses" \
  -H "Content-Type: application/json" \
  -d '{"id": "presidio-gc", "name": "Presidio Golf Course", "city": "San Francisco", "state": "CA", "numHoles": 18}' \
  | python3 -m json.tool
```

Response (201):
```json
{
  "course": { "id": "presidio-gc", "name": "Presidio Golf Course", "city": "San Francisco", "state": "CA", "numHoles": 18 }
}
```

#### `get_course` — Get course details with holes

Returns course metadata and a list of all registered holes with their status.

```bash
curl -s "$API/courses/presidio-gc" | python3 -m json.tool
```

Response:
```json
{
  "course": {
    "id": "presidio-gc",
    "name": "PresidioGC",
    "numHoles": 18,
    "holes": [
      { "holeNum": 1, "greenWidthFt": 102.4, "greenHeightFt": 83.7, "hasSource": true, "hasProcessed": true }
    ]
  }
}
```

#### `get_hole` — Get hole details with CDN URLs

Returns hole metadata and CloudFront URLs for source/processed files (only if `hasSource`/`hasProcessed` is true).

```bash
curl -s "$API/courses/presidio-gc/holes/1" | python3 -m json.tool
```

Response:
```json
{
  "hole": {
    "courseId": "presidio-gc",
    "holeNum": 1,
    "greenWidthFt": 102.4,
    "greenHeightFt": 83.7,
    "hasSource": true,
    "hasProcessed": true,
    "sourceUrls": {
      "image.png": "https://dewsnbw2ryf8i.cloudfront.net/presidio-gc/1/source/image.png",
      "boundary.json": "https://dewsnbw2ryf8i.cloudfront.net/presidio-gc/1/source/boundary.json",
      "contours.json": "https://dewsnbw2ryf8i.cloudfront.net/presidio-gc/1/source/contours.json"
    },
    "processedUrls": {
      "heightfield.json": "https://dewsnbw2ryf8i.cloudfront.net/presidio-gc/1/processed/heightfield.json",
      "heightfield.bin": "https://dewsnbw2ryf8i.cloudfront.net/presidio-gc/1/processed/heightfield.bin"
    }
  }
}
```

#### `register_hole` — Register a hole and get upload URLs

Creates/overwrites a hole record and returns pre-signed S3 upload URLs for all expected files. Used by the CLI `upload` command.

```bash
curl -s -X POST "$API/courses/presidio-gc/holes/1" \
  -H "Content-Type: application/json" \
  -d '{"greenWidthFt": 102.4, "greenHeightFt": 83.7}' \
  | python3 -m json.tool
```

Response (201):
```json
{
  "holeNum": 1,
  "uploadUrls": {
    "source": {
      "image.png": "https://greenreader-data.s3.amazonaws.com/presidio-gc/1/source/image.png?X-Amz-...",
      "boundary.json": "...",
      "contours.json": "..."
    },
    "processed": {
      "heightfield.json": "...",
      "heightfield.bin": "..."
    }
  }
}
```

Upload a file using the returned pre-signed URL:
```bash
curl -X PUT "<presigned-url>" \
  -H "Content-Type: image/png" \
  --data-binary @Hole_1.png
```

#### `update_hole` — Update hole metadata

Updates specific fields on an existing hole. Used after uploading files to set status flags.

```bash
curl -s -X PUT "$API/courses/presidio-gc/holes/1" \
  -H "Content-Type: application/json" \
  -d '{"hasSource": true, "hasProcessed": true}' \
  | python3 -m json.tool
```

Allowed fields: `hasSource`, `hasProcessed`, `greenWidthFt`, `greenHeightFt`, `holeXzFt`

Response:
```json
{
  "hole": {
    "courseId": "presidio-gc",
    "holeNum": 1,
    "hasSource": true,
    "hasProcessed": true,
    "greenWidthFt": 102.4,
    "greenHeightFt": 83.7
  }
}
```

#### `compute_bestline` — Compute optimal putt line

Downloads the heightfield from S3, runs a coarse-to-fine ball roll simulation, and returns the optimal launch parameters and full ball path. Runs with 512MB memory and a 30-second timeout.

```bash
curl -s -X POST "$API/courses/presidio-gc/holes/1/bestline" \
  -H "Content-Type: application/json" \
  -d '{"ballXFt": -11.68, "ballZFt": 2.27, "holeXFt": 28.32, "holeZFt": -2.73, "stimpFt": 10.0}' \
  | python3 -m json.tool
```

Required fields: `ballXFt`, `ballZFt`
Optional fields: `holeXFt`, `holeZFt` (defaults to stored metadata), `stimpFt` (defaults to 10.0)

Response:
```json
{
  "bestLine": {
    "ballXFt": -11.68,
    "ballZFt": 2.27,
    "holeXFt": 28.32,
    "holeZFt": -2.73,
    "stimpFt": 10.0,
    "aimOffsetDeg": 16.6,
    "speedFps": 10.0,
    "v0XFps": 9.86,
    "v0ZFps": 1.65,
    "holed": true,
    "missFt": 0.176,
    "tEndS": 6.46,
    "pathXFt": ["-11.68", "..."],
    "pathZFt": ["2.27", "..."],
    "pathYFt": ["0.42", "..."]
  }
}
```

### Shared Layer

**Lambda Layer** (`lambdas/layer/python/shared/`):
- `db.py` — DynamoDB table access, float-to-Decimal conversion
- `s3.py` — Pre-signed upload URL generation, CloudFront URL builder
- `response.py` — JSON response helpers with CORS headers and Decimal serialization
- `log.py` — JSON-structured logging for CloudWatch Logs Insights

**Compute Lambda bundling:**

The `compute_bestline` Lambda is built differently from the CRUD handlers. At `cdk synth` time, CDK uses Docker to:
1. Install `numpy` via pip
2. Copy `backend/terrain/{heightmap,green}.py` and `backend/physics/{ball_roll_stimp,best_line_refine}.py` from the project source
3. Package everything into a single deployment zip

This keeps the backend physics code as the single source of truth — no duplication in the repo. The compute Lambda runs with 512MB memory and a 30-second timeout.

**IAM permissions** (granted automatically by CDK):
- CRUD Lambda functions get read/write access to DynamoDB and S3
- Compute Lambda gets read-only access to DynamoDB and S3

## Stack Outputs

After deployment, the stack exports:

| Output | Value |
|--------|-------|
| `ApiUrl` | API Gateway base URL (e.g. `https://xxx.execute-api.us-west-2.amazonaws.com/prod/`) |
| `CdnDomain` | CloudFront domain (e.g. `d1234abcdef.cloudfront.net`) |
| `BucketName` | S3 bucket name |

## Commands

```bash
cd infra

npm install          # Install dependencies
npx cdk synth        # Synthesize CloudFormation template (validates everything)
npx cdk deploy       # Deploy to AWS
npx cdk destroy      # Tear down all resources
```

## Observability

All Lambdas emit JSON-structured logs and have X-Ray tracing enabled.

**CloudWatch Logs Insights queries:**

```
# Find all errors across all Lambdas
fields @timestamp, level, message, course_id, hole_num, exception
| filter level = "ERROR"
| sort @timestamp desc

# API Gateway access logs — find slow or failed requests
fields @timestamp, httpMethod, resourcePath, status, responseLatency
| filter status >= 400
| sort @timestamp desc

# Track bestline compute performance
fields @timestamp, message, course_id, hole_num
| filter logger = "index" and message like /Bestline computed/
| sort @timestamp desc
```

**Configuration:**
- Lambda log retention: 2 weeks
- API Gateway access logs: JSON format, 2 weeks retention
- X-Ray tracing: active on all Lambdas
- Log level: controlled via `LOG_LEVEL` env var (default: `INFO`)

## Project Structure

```
infra/
  bin/
    app.ts                  # CDK app entry point
  lib/
    greenreader-stack.ts    # Main stack (composes constructs)
    constants.ts            # Resource names and config
    storage.ts              # S3 + DynamoDB
    cdn.ts                  # CloudFront distribution
    api.ts                  # API Gateway + Lambda functions + Layer
  cdk.json                  # CDK config (uses ts-node, no build step needed)
  package.json
  tsconfig.json
```
