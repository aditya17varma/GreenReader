"""
GreenReader backend CLI.

Usage:
    python -m backend.cli build <course_name>          Build all holes
    python -m backend.cli build <course_name> <hole>   Build a single hole
    python -m backend.cli upload <course> --course-id <slug> [--api-url <url>] [--hole <Hole_X>]
"""

import argparse
import json
import os
import sys
import logging
from urllib.parse import urlsplit, urlunsplit

import numpy as np
import requests
from shapely.geometry import Polygon

from backend.maps import GreenExtentsLatLon, infer_green_size_ft
from backend.maps.green_map_scale import make_local_grid_ft
from backend.terrain.contour_reconstruct import reconstruct_heightfield_from_contours
from backend.tools import paths


LOG_LEVEL = os.environ.get("GREENREADER_LOG_LEVEL", "INFO").upper()
logging.basicConfig(level=LOG_LEVEL, format="%(levelname)s: %(message)s")
logger = logging.getLogger("greenreader.cli")


def _safe_url(url: str) -> str:
    parts = urlsplit(url)
    return urlunsplit((parts.scheme, parts.netloc, parts.path, "", ""))


def _request(method: str, url: str, **kwargs) -> requests.Response:
    safe_url = _safe_url(url)
    logger.info("%s %s", method.upper(), safe_url)
    if "json" in kwargs and isinstance(kwargs["json"], dict):
        logger.debug("JSON keys: %s", list(kwargs["json"].keys()))
    resp = requests.request(method, url, **kwargs)
    logger.info("%s %s -> %s", method.upper(), safe_url, resp.status_code)
    if resp.status_code >= 400:
        body_preview = resp.text[:500]
        logger.error("Error body: %s", body_preview)
    return resp


def load_config(course_name: str, hole_name: str) -> dict:
    cfg_file = paths.config_path(course_name, hole_name)
    with open(cfg_file, "r") as f:
        return json.load(f)


def extents_from_config(cfg: dict) -> GreenExtentsLatLon:
    e = cfg["extents"]
    return GreenExtentsLatLon(
        north=(e["north"]["lat"], e["north"]["lon"]),
        south=(e["south"]["lat"], e["south"]["lon"]),
        east=(e["east"]["lat"], e["east"]["lon"]),
        west=(e["west"]["lat"], e["west"]["lon"]),
    )


def validate_hole(course_name: str, hole_name: str) -> list[str]:
    """Return list of missing files (empty = valid)."""
    missing = []
    checks = [
        ("config.json", paths.config_path),
        ("contour PNG", paths.contour_path),
        ("boundary JSON", paths.boundary_path),
        ("contours JSON", paths.contours_path),
    ]
    for label, path_fn in checks:
        p = path_fn(course_name, hole_name)
        if not os.path.isfile(p):
            missing.append(f"{label} ({p})")
    return missing


def discover_holes(course_name: str) -> list[str]:
    """Find all Hole_* directories in a course folder."""
    cdir = paths.course_dir(course_name)
    if not os.path.isdir(cdir):
        return []
    return sorted(
        d for d in os.listdir(cdir)
        if d.startswith("Hole_") and os.path.isdir(os.path.join(cdir, d))
    )


def build_hole(course_name: str, hole_name: str) -> bool:
    """Build heightfield for a single hole. Returns True on success."""
    # 1. Validate
    missing = validate_hole(course_name, hole_name)
    if missing:
        for m in missing:
            print(f"  MISSING: {m}")
        return False

    # 2. Load config
    cfg = load_config(course_name, hole_name)
    extents = extents_from_config(cfg)
    green_width_ft, green_height_ft = infer_green_size_ft(extents)

    # 3. Load boundary
    with open(paths.boundary_path(course_name, hole_name)) as f:
        b = json.load(f)
    boundary_poly = Polygon([(p["x"], p["z"]) for p in b["points_xz_ft"]])

    # 4. Load contours
    with open(paths.contours_path(course_name, hole_name)) as f:
        c = json.load(f)
    contours_in = []
    for item in c["contours"]:
        pts = [(p["x"], p["z"]) for p in item["points_xz_ft"]]
        contours_in.append({"height_ft": float(item["height_ft"]), "points_xz": pts})

    # 5. Reconstruct heightfield
    resolution_ft = 0.5
    X, Z = make_local_grid_ft(green_width_ft, green_height_ft, resolution_ft)

    Y, inside = reconstruct_heightfield_from_contours(
        boundary_poly=boundary_poly,
        contours=contours_in,
        grid_x=X,
        grid_z=Z,
        sample_step_ft=1.0,
        smooth=0.25,
    )

    Y_filled = np.nan_to_num(Y, nan=0.0).astype(np.float32)

    # 6. Write outputs
    out_dir = paths.unity_dir(course_name, hole_name)
    os.makedirs(out_dir, exist_ok=True)

    bin_path = paths.heightfield_bin_path(course_name, hole_name)
    meta_path = paths.heightfield_json_path(course_name, hole_name)

    Y_filled.tofile(bin_path)

    meta = {
        "units": {"x": "ft", "z": "ft", "y": "ft"},
        "grid": {
            "nx": int(Y_filled.shape[1]),
            "nz": int(Y_filled.shape[0]),
            "resolution_ft": float(resolution_ft),
            "x_min_ft": float(np.min(X)),
            "z_min_ft": float(np.min(Z)),
        },
        "mask": {
            "format": "uint8",
            "note": "mask array not written yet; inside=true",
        },
    }

    with open(meta_path, "w") as f:
        json.dump(meta, f, indent=2)

    print(f"  Wrote: {bin_path}")
    print(f"  Wrote: {meta_path}")
    print(f"  Grid: nx={meta['grid']['nx']}, nz={meta['grid']['nz']}, res={resolution_ft}ft")
    return True


def cmd_build(args):
    """Handle the 'build' subcommand."""
    course_name = args.course

    if args.hole:
        holes = [args.hole]
    else:
        holes = discover_holes(course_name)

    if not holes:
        print(f"No Hole_* folders found in {paths.course_dir(course_name)}")
        sys.exit(1)

    results = {}
    for hole_name in holes:
        print(f"\n--- Building {course_name}/{hole_name} ---")
        success = build_hole(course_name, hole_name)
        results[hole_name] = success

    # Summary
    print("\n=== Build Summary ===")
    for hole, ok in results.items():
        status = "OK" if ok else "FAILED"
        print(f"  {hole}: {status}")

    if not all(results.values()):
        sys.exit(1)


# ---------------------------------------------------------------------------
# upload command
# ---------------------------------------------------------------------------

SOURCE_FILES = {
    "contour.png": "image/png",
    "map.png": "image/png",
    "boundary.json": "application/json",
    "contours.json": "application/json",
}

PROCESSED_FILES = {
    "heightfield.json": "application/json",
    "heightfield.bin": "application/octet-stream",
}


def _local_source_files(course_name: str, hole_name: str) -> dict[str, str | None]:
    """Map S3 file names → local paths (None if missing)."""
    return {
        "contour.png": paths.contour_path(course_name, hole_name),
        "map.png": paths.map_path(course_name, hole_name),
        "boundary.json": paths.boundary_path(course_name, hole_name),
        "contours.json": paths.contours_path(course_name, hole_name),
    }


def _local_processed_files(course_name: str, hole_name: str) -> dict[str, str | None]:
    return {
        "heightfield.json": paths.heightfield_json_path(course_name, hole_name),
        "heightfield.bin": paths.heightfield_bin_path(course_name, hole_name),
    }


def _hole_num_from_name(hole_name: str) -> int:
    """Extract hole number: 'Hole_1' → 1, 'Hole_12' → 12."""
    return int(hole_name.split("_", 1)[1])


def upload_file(local_path: str, presigned_url: str, content_type: str):
    """Upload a file to S3 using a pre-signed URL."""
    print(f"    Uploading {os.path.basename(local_path)}...")
    with open(local_path, "rb") as f:
        resp = _request(
            "PUT",
            presigned_url,
            data=f,
            headers={"Content-Type": content_type},
        )
    resp.raise_for_status()


def upload_hole(api_url: str, course_id: str,
                course_name: str, hole_name: str) -> bool:
    """Register, upload files, and update status for a single hole."""
    hole_num = _hole_num_from_name(hole_name)

    # Check which local files exist
    source_map = _local_source_files(course_name, hole_name)
    processed_map = _local_processed_files(course_name, hole_name)

    existing_source = {
        name: path for name, path in source_map.items()
        if os.path.isfile(path)
    }
    existing_processed = {
        name: path for name, path in processed_map.items()
        if os.path.isfile(path)
    }

    if not existing_source:
        print("  SKIP: no source files found")
        return False

    # Read green dimensions from boundary JSON if available
    reg_body: dict = {}
    bnd_path = source_map["boundary.json"]
    if os.path.isfile(bnd_path):
        with open(bnd_path, "r") as f:
            bnd = json.load(f)
        if "green_width_ft" in bnd:
            reg_body["greenWidthFt"] = bnd["green_width_ft"]
        if "green_height_ft" in bnd:
            reg_body["greenHeightFt"] = bnd["green_height_ft"]

    # 1. Register hole → get pre-signed URLs
    print(f"  Registering hole {hole_num}...")
    resp = _request(
        "POST",
        f"{api_url}/courses/{course_id}/holes/{hole_num}",
        json=reg_body,
    )
    resp.raise_for_status()
    urls = resp.json()["uploadUrls"]

    # 2. Upload source files
    has_source = False
    for name, local_path in existing_source.items():
        upload_file(local_path, urls["source"][name], SOURCE_FILES[name])
        has_source = True

    # 3. Upload processed files
    has_processed = False
    for name, local_path in existing_processed.items():
        upload_file(local_path, urls["processed"][name], PROCESSED_FILES[name])
        has_processed = True

    # 4. Update hole status flags
    update_body: dict = {}
    if has_source:
        update_body["hasSource"] = True
    if has_processed:
        update_body["hasProcessed"] = True

    if update_body:
        resp = _request(
            "PUT",
            f"{api_url}/courses/{course_id}/holes/{hole_num}",
            json=update_body,
        )
        resp.raise_for_status()

    src_count = len(existing_source)
    proc_count = len(existing_processed)
    print(f"  Uploaded {src_count} source, {proc_count} processed files")
    return True


def ensure_course(api_url: str, course_id: str, display_name: str):
    """Create the course if it doesn't already exist."""
    resp = _request("GET", f"{api_url}/courses/{course_id}")
    if resp.status_code == 200:
        print(f"Course '{course_id}' already exists")
        return
    print(f"Creating course '{course_id}'...")
    resp = _request(
        "POST",
        f"{api_url}/courses",
        json={"id": course_id, "name": display_name},
    )
    resp.raise_for_status()
    print(f"Course '{course_id}' created")


def cmd_upload(args):
    """Handle the 'upload' subcommand."""
    course_name = args.course
    course_id = args.course_id
    api_url = args.api_url or os.environ.get("GREENREADER_API_URL")

    if not api_url:
        print("Error: --api-url is required (or set GREENREADER_API_URL env var)")
        sys.exit(1)

    api_url = api_url.rstrip("/")

    # Ensure the course record exists in DynamoDB
    ensure_course(api_url, course_id, course_name)

    if args.hole:
        holes = [args.hole]
    else:
        holes = discover_holes(course_name)

    if not holes:
        print(f"No Hole_* folders found in {paths.course_dir(course_name)}")
        sys.exit(1)

    results = {}
    for hole_name in holes:
        print(f"\n--- Uploading {course_name}/{hole_name} ---")
        try:
            success = upload_hole(api_url, course_id, course_name, hole_name)
        except requests.HTTPError as e:
            print(f"  ERROR: {e}")
            if e.response is not None:
                print(f"  Response body: {e.response.text}")
            success = False
        results[hole_name] = success

    # Summary
    print("\n=== Upload Summary ===")
    for hole, ok in results.items():
        status = "OK" if ok else "FAILED"
        print(f"  {hole}: {status}")

    if not all(results.values()):
        sys.exit(1)


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        prog="backend.cli",
        description="GreenReader backend CLI",
    )
    sub = parser.add_subparsers(dest="command")

    # build subcommand
    build_p = sub.add_parser("build", help="Build heightfields for a course")
    build_p.add_argument("course", help="Course name (e.g. PresidioGC)")
    build_p.add_argument("hole", nargs="?", default=None,
                         help="Optional hole name (e.g. Hole_1)")
    build_p.set_defaults(func=cmd_build)

    # upload subcommand
    upload_p = sub.add_parser("upload", help="Upload hole data to AWS")
    upload_p.add_argument("course", help="Local course folder name (e.g. PresidioGC)")
    upload_p.add_argument("--course-id", required=True,
                          help="API course ID slug (e.g. presidio-gc)")
    upload_p.add_argument("--api-url", default=None,
                          help="API base URL (or set GREENREADER_API_URL env var)")
    upload_p.add_argument("--hole", default=None,
                          help="Upload a single hole (e.g. Hole_1)")
    upload_p.set_defaults(func=cmd_upload)

    args = parser.parse_args()
    if not args.command:
        parser.print_help()
        sys.exit(1)
    args.func(args)


if __name__ == "__main__":
    main()
