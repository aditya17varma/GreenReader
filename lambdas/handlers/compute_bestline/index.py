import io
import json
import struct

import boto3
import numpy as np

from terrain.heightmap import HeightMap
from physics.ball_roll_stimp import BallRollSimulatorStimp
from physics.best_line_refine import best_line_coarse_to_fine

from shared.response import error, success
from shared.s3 import get_bucket

s3 = boto3.client("s3")

DEFAULT_STIMP_FT = 10.0


def _load_heightmap(course_id, hole_num):
    """Download heightfield.json + heightfield.bin from S3 and reconstruct a HeightMap."""
    bucket = get_bucket()
    prefix = f"{course_id}/{hole_num}/processed"

    # Load metadata
    meta_obj = s3.get_object(Bucket=bucket, Key=f"{prefix}/heightfield.json")
    meta = json.loads(meta_obj["Body"].read())

    grid = meta["grid"]
    nx = grid["nx"]
    nz = grid["nz"]
    res = grid["resolution_ft"]
    x_min = grid["x_min_ft"]
    z_min = grid["z_min_ft"]

    # Load binary elevation data
    bin_obj = s3.get_object(Bucket=bucket, Key=f"{prefix}/heightfield.bin")
    raw = bin_obj["Body"].read()
    Y = np.frombuffer(raw, dtype=np.float32).reshape((nz, nx))

    # Reconstruct grid arrays
    x_axis = np.arange(nx) * res + x_min
    z_axis = np.arange(nz) * res + z_min
    X, Z = np.meshgrid(x_axis, z_axis)

    # Mask: cells with non-zero elevation are inside the green
    mask = Y > 0.0

    hm = HeightMap(X=X, Z=Z, Y=Y.astype(np.float64), resolution_ft=res, mask=mask)
    hm.compute_gradients()

    hole_xz = meta.get("hole_xz_ft", {})
    return hm, hole_xz


def handler(event, context):
    course_id = event["pathParameters"]["courseId"]
    hole_num = event["pathParameters"]["holeNum"]

    try:
        body = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        return error("Invalid JSON body")

    ball_x = body.get("ballXFt")
    ball_z = body.get("ballZFt")
    if ball_x is None or ball_z is None:
        return error("Missing required fields: ballXFt, ballZFt")

    stimp_ft = body.get("stimpFt", DEFAULT_STIMP_FT)

    # Load heightfield from S3
    try:
        hm, stored_hole = _load_heightmap(course_id, hole_num)
    except s3.exceptions.NoSuchKey:
        return error("Heightfield not found for this hole", 404)
    except Exception as e:
        return error(f"Failed to load heightfield: {str(e)}", 500)

    # Hole position: use request body or fall back to stored metadata
    hole_x = body.get("holeXFt", stored_hole.get("x"))
    hole_z = body.get("holeZFt", stored_hole.get("z"))
    if hole_x is None or hole_z is None:
        return error("Hole position not provided and not found in heightfield metadata")

    ball_x = float(ball_x)
    ball_z = float(ball_z)
    hole_x = float(hole_x)
    hole_z = float(hole_z)
    stimp_ft = float(stimp_ft)

    # Run simulation
    sim = BallRollSimulatorStimp(hm, stimp_ft=stimp_ft)
    result = best_line_coarse_to_fine(
        sim,
        ball_x_ft=ball_x,
        ball_z_ft=ball_z,
        hole_x_ft=hole_x,
        hole_z_ft=hole_z,
    )

    res = result["result"]

    return success({
        "bestLine": {
            "ballXFt": ball_x,
            "ballZFt": ball_z,
            "holeXFt": hole_x,
            "holeZFt": hole_z,
            "stimpFt": stimp_ft,
            "aimOffsetDeg": result["angle_deg"],
            "speedFps": result["speed_fps"],
            "v0XFps": result["v0_x_fps"],
            "v0ZFps": result["v0_z_fps"],
            "holed": res["holed"],
            "missFt": result["miss_ft"],
            "tEndS": res["t_end"],
            "pathXFt": res["path_x"].tolist(),
            "pathZFt": res["path_z"].tolist(),
            "pathYFt": res["path_y"].tolist(),
        }
    })
