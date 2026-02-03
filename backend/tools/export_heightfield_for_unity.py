import json
import os
import sys
import numpy as np
from shapely.geometry import Polygon

from backend.maps import GreenExtentsLatLon, infer_green_size_ft
from backend.maps.green_map_scale import make_local_grid_ft
from backend.terrain.contour_reconstruct import reconstruct_heightfield_from_contours
from backend.tools.paths import (
    config_path, boundary_path, contours_path,
    unity_dir, heightfield_bin_path, heightfield_json_path,
)


def main(course_name: str, hole_name: str):
    # Load config
    cfg_file = config_path(course_name, hole_name)
    with open(cfg_file, "r") as f:
        cfg = json.load(f)

    e = cfg["extents"]
    extents = GreenExtentsLatLon(
        north=(e["north"]["lat"], e["north"]["lon"]),
        south=(e["south"]["lat"], e["south"]["lon"]),
        east=(e["east"]["lat"], e["east"]["lon"]),
        west=(e["west"]["lat"], e["west"]["lon"]),
    )
    green_width_ft, green_height_ft = infer_green_size_ft(extents)

    # Load boundary
    bnd_file = boundary_path(course_name, hole_name)
    with open(bnd_file, "r") as f:
        b = json.load(f)
    boundary_poly = Polygon([(p["x"], p["z"]) for p in b["points_xz_ft"]])

    # Load contours
    ctr_file = contours_path(course_name, hole_name)
    with open(ctr_file, "r") as f:
        c = json.load(f)

    contours_in = []
    for item in c["contours"]:
        pts = [(p["x"], p["z"]) for p in item["points_xz_ft"]]
        contours_in.append({"height_ft": float(item["height_ft"]), "points_xz": pts})

    # Reconstruct heightfield
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

    # Write outputs
    out_dir = unity_dir(course_name, hole_name)
    os.makedirs(out_dir, exist_ok=True)

    bin_path = heightfield_bin_path(course_name, hole_name)
    meta_path = heightfield_json_path(course_name, hole_name)

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

    print(f"Wrote:\n  {bin_path}\n  {meta_path}")
    print(f"Grid: nx={meta['grid']['nx']}, nz={meta['grid']['nz']}, res={resolution_ft}ft")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python -m backend.tools.export_heightfield_for_unity <course_name> <hole_name>")
        print("Example: python -m backend.tools.export_heightfield_for_unity PresidioGC Hole_1")
        sys.exit(1)
    main(course_name=sys.argv[1], hole_name=sys.argv[2])
