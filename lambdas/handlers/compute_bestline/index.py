import json
from datetime import datetime, timezone

import boto3
import numpy as np

from terrain.heightmap import HeightMap
from physics.ball_roll_stimp import BallRollSimulatorStimp
from physics.best_line_refine import best_line_coarse_to_fine

from shared.db import get_job_table, to_dynamo, bestline_job_key
from shared.log import get_logger
from shared.s3 import get_bucket

logger = get_logger(__name__)

s3 = boto3.client("s3")

DEFAULT_STIMP_FT = 10.0


def _now_iso():
    return datetime.now(timezone.utc).isoformat()


def _update_job(course_id, hole_num, job_id, updates):
    if not job_id:
        return
    try:
        table = get_job_table()
        updates = {**updates, "updatedAt": _now_iso()}
        update_expr_parts = []
        expr_names = {}
        expr_values = {}
        for idx, (key, value) in enumerate(updates.items()):
            name_key = f"#k{idx}"
            value_key = f":v{idx}"
            update_expr_parts.append(f"{name_key} = {value_key}")
            expr_names[name_key] = key
            expr_values[value_key] = to_dynamo(value)

        table.update_item(
            Key=bestline_job_key(course_id, hole_num, job_id),
            UpdateExpression="SET " + ", ".join(update_expr_parts),
            ExpressionAttributeNames=expr_names,
            ExpressionAttributeValues=expr_values,
        )
    except Exception:
        logger.exception(
            "Failed to update bestline job",
            extra={"course_id": course_id, "hole_num": hole_num, "job_id": job_id},
        )


def _load_heightmap(course_id, hole_num):
    """Download heightfield.json + heightfield.bin from S3 and reconstruct a HeightMap."""
    bucket = get_bucket()
    prefix = f"{course_id}/{hole_num}/processed"

    logger.info("Loading heightfield metadata from S3: %s/heightfield.json", prefix)
    meta_obj = s3.get_object(Bucket=bucket, Key=f"{prefix}/heightfield.json")
    meta = json.loads(meta_obj["Body"].read())

    grid = meta["grid"]
    nx = grid["nx"]
    nz = grid["nz"]
    res = grid["resolution_ft"]
    x_min = grid["x_min_ft"]
    z_min = grid["z_min_ft"]

    logger.info("Loading heightfield binary from S3: %s/heightfield.bin", prefix)
    bin_obj = s3.get_object(Bucket=bucket, Key=f"{prefix}/heightfield.bin")
    raw = bin_obj["Body"].read()
    Y = np.frombuffer(raw, dtype=np.float32).reshape((nz, nx))

    x_axis = np.arange(nx) * res + x_min
    z_axis = np.arange(nz) * res + z_min
    X, Z = np.meshgrid(x_axis, z_axis)

    mask = Y > 0.0

    hm = HeightMap(X=X, Z=Z, Y=Y.astype(np.float64), resolution_ft=res, mask=mask)
    hm.compute_gradients()

    return hm


def handler(event, context):
    job = event["job"]
    job_id = job.get("jobId")
    course_id = job["courseId"]
    hole_num = job["holeNum"]
    ctx = {"course_id": course_id, "hole_num": hole_num, "job_id": job_id}
    logger.info("Computing bestline job", extra=ctx)

    try:
        body = job.get("params") or {}

        ball_x = body.get("ballXFt")
        ball_z = body.get("ballZFt")
        hole_x = body.get("holeXFt")
        hole_z = body.get("holeZFt")
        if ball_x is None or ball_z is None or hole_x is None or hole_z is None:
            _update_job(course_id, hole_num, job_id, {"status": "failed", "error": "Missing required position fields"})
            return {"status": "error"}

        stimp_ft = body.get("stimpFt", DEFAULT_STIMP_FT)

        ball_x = float(ball_x)
        ball_z = float(ball_z)
        hole_x = float(hole_x)
        hole_z = float(hole_z)
        stimp_ft = float(stimp_ft)

        # Load heightfield from S3
        try:
            hm = _load_heightmap(course_id, hole_num)
        except Exception:
            logger.exception("Failed to load heightfield", extra=ctx)
            _update_job(course_id, hole_num, job_id, {"status": "failed", "error": "Failed to load heightfield"})
            return {"status": "error"}

        # Run simulation
        _update_job(course_id, hole_num, job_id, {"status": "running", "startedAt": _now_iso()})

        logger.info("Running simulation: ball=(%.2f, %.2f) hole=(%.2f, %.2f) stimp=%.1f",
                     ball_x, ball_z, hole_x, hole_z, stimp_ft, extra=ctx)
        sim = BallRollSimulatorStimp(hm, stimp_ft=stimp_ft)
        result = best_line_coarse_to_fine(
            sim,
            ball_x_ft=ball_x,
            ball_z_ft=ball_z,
            hole_x_ft=hole_x,
            hole_z_ft=hole_z,
        )

        res = result["result"]

        bestline = {
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

        logger.info("Bestline computed: holed=%s miss_ft=%.3f", res["holed"], result["miss_ft"], extra=ctx)

        result_key = job.get("resultKey")
        if result_key:
            s3.put_object(
                Bucket=get_bucket(),
                Key=result_key,
                Body=json.dumps({"bestLine": bestline}).encode("utf-8"),
                ContentType="application/json",
            )
        _update_job(
            course_id,
            hole_num,
            job_id,
            {
                "status": "completed",
                "completedAt": _now_iso(),
                "resultKey": result_key,
                "cacheKey": job.get("cacheKey"),
            },
        )
        return {"status": "ok"}
    except Exception:
        logger.exception("Failed to compute bestline", extra=ctx)
        _update_job(course_id, hole_num, job_id, {"status": "failed", "error": "Internal server error"})
        return {"status": "error"}
