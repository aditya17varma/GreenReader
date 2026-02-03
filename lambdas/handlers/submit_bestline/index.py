import json
import hashlib
import os
import uuid
from datetime import datetime, timezone, timedelta

import boto3
from botocore.exceptions import ClientError

from shared.db import get_job_table, to_dynamo, bestline_job_key
from shared.log import get_logger
from shared.response import error, success
from shared.s3 import get_bucket

logger = get_logger(__name__)

s3 = boto3.client("s3")
lambda_client = boto3.client("lambda")

DEFAULT_STIMP_FT = 10.0
JOB_TIMEOUT_SECONDS = 300
JOB_TTL_SECONDS = 86400  # 24 hours


def _now_iso():
    return datetime.now(timezone.utc).isoformat()



def _heightfield_etag(course_id, hole_num):
    prefix = f"{course_id}/{hole_num}/processed"
    bucket = get_bucket()
    bin_obj = s3.head_object(Bucket=bucket, Key=f"{prefix}/heightfield.bin")
    json_obj = s3.head_object(Bucket=bucket, Key=f"{prefix}/heightfield.json")
    bin_etag = bin_obj["ETag"].strip('"')
    json_etag = json_obj["ETag"].strip('"')
    return f"{bin_etag}:{json_etag}"


def _cache_key(payload):
    raw = json.dumps(payload, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


def _cache_key_path(course_id, hole_num, cache_key):
    return f"{course_id}/{hole_num}/bestline-cache/{cache_key}.json"


def handler(event, context):
    course_id = event["pathParameters"]["courseId"]
    hole_num = event["pathParameters"]["holeNum"]
    ctx = {"course_id": course_id, "hole_num": hole_num}
    logger.info("Submitting bestline job", extra=ctx)

    try:
        try:
            body = json.loads(event.get("body") or "{}")
        except json.JSONDecodeError:
            return error("Invalid JSON body")

        ball_x = body.get("ballXFt")
        ball_z = body.get("ballZFt")
        hole_x = body.get("holeXFt")
        hole_z = body.get("holeZFt")
        if ball_x is None or ball_z is None or hole_x is None or hole_z is None:
            return error("Missing required fields: ballXFt, ballZFt, holeXFt, holeZFt")

        stimp_ft = float(body.get("stimpFt", DEFAULT_STIMP_FT))

        try:
            heightfield_etag = _heightfield_etag(course_id, hole_num)
        except ClientError as exc:
            if exc.response.get("Error", {}).get("Code") == "404":
                return error("Heightfield not found for this hole", 404)
            logger.exception("Failed to load heightfield metadata", extra=ctx)
            return error("Failed to load heightfield metadata", 500)

        cache_payload = {
            "courseId": course_id,
            "holeNum": int(hole_num),
            "ballXFt": float(ball_x),
            "ballZFt": float(ball_z),
            "holeXFt": float(hole_x),
            "holeZFt": float(hole_z),
            "stimpFt": stimp_ft,
            "heightfieldEtag": heightfield_etag,
        }
        cache_key = _cache_key(cache_payload)
        result_key = _cache_key_path(course_id, hole_num, cache_key)

        try:
            cached = s3.get_object(Bucket=get_bucket(), Key=result_key)
            cached_body = cached["Body"].read()
            return success(json.loads(cached_body))
        except ClientError as exc:
            if exc.response.get("Error", {}).get("Code") not in ("NoSuchKey", "404"):
                logger.exception("Failed to read cache", extra=ctx)
                return error("Failed to read cache", 500)

        job_id = uuid.uuid4().hex
        now = datetime.now(timezone.utc)
        timeout_at = now + timedelta(seconds=JOB_TIMEOUT_SECONDS)
        ttl_epoch = int((now + timedelta(seconds=JOB_TTL_SECONDS)).timestamp())
        job_item = {
            **bestline_job_key(course_id, hole_num, job_id),
            "jobId": job_id,
            "courseId": course_id,
            "holeNum": int(hole_num),
            "status": "queued",
            "createdAt": _now_iso(),
            "updatedAt": _now_iso(),
            "timeoutAt": timeout_at.isoformat(),
            "ttl": ttl_epoch,
            "params": {
                "ballXFt": float(ball_x),
                "ballZFt": float(ball_z),
                "holeXFt": float(hole_x),
                "holeZFt": float(hole_z),
                "stimpFt": stimp_ft,
            },
            "cacheKey": cache_key,
            "resultKey": result_key,
            "heightfieldEtag": heightfield_etag,
        }
        table = get_job_table()
        table.put_item(Item=to_dynamo(job_item))

        lambda_client.invoke(
            FunctionName=os.environ["COMPUTE_BESTLINE_FUNCTION"],
            InvocationType="Event",
            Payload=json.dumps(
                {
                    "job": {
                        "jobId": job_id,
                        "courseId": course_id,
                        "holeNum": hole_num,
                        "params": job_item["params"],
                        "cacheKey": cache_key,
                        "resultKey": result_key,
                        "heightfieldEtag": heightfield_etag,
                    }
                }
            ).encode("utf-8"),
        )

        return success({"jobId": job_id, "status": "queued"})
    except Exception:
        logger.exception("Failed to submit bestline job", extra=ctx)
        return error("Internal server error", 500)
