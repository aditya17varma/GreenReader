import json
from datetime import datetime, timezone

import boto3
from botocore.exceptions import ClientError

from shared.db import get_job_table, bestline_job_key
from shared.log import get_logger
from shared.response import error, success
from shared.s3 import get_bucket

logger = get_logger(__name__)

s3 = boto3.client("s3")
STALE_JOB_SECONDS = 300



def handler(event, context):
    course_id = event["pathParameters"]["courseId"]
    hole_num = event["pathParameters"]["holeNum"]
    job_id = event["pathParameters"]["jobId"]
    ctx = {"course_id": course_id, "hole_num": hole_num, "job_id": job_id}
    logger.info("Fetching bestline job", extra=ctx)

    try:
        table = get_job_table()
        resp = table.get_item(Key=bestline_job_key(course_id, hole_num, job_id))
        item = resp.get("Item")
        if not item:
            return error("Bestline job not found", 404)

        status = item.get("status")
        if status == "completed":
            result_key = item.get("resultKey")
            if not result_key:
                return error("Bestline result missing", 500)
            try:
                cached = s3.get_object(Bucket=get_bucket(), Key=result_key)
                cached_body = cached["Body"].read()
                return success(json.loads(cached_body))
            except ClientError:
                logger.exception("Failed to read cached result", extra=ctx)
                return error("Failed to load bestline result", 500)

        if status == "failed":
            return error(item.get("error", "Bestline computation failed"), 500)

        updated_at = item.get("updatedAt")
        if updated_at:
            try:
                updated_dt = datetime.fromisoformat(updated_at)
                if updated_dt.tzinfo is None:
                    updated_dt = updated_dt.replace(tzinfo=timezone.utc)
                age_seconds = (datetime.now(timezone.utc) - updated_dt).total_seconds()
                if age_seconds > STALE_JOB_SECONDS:
                    table.update_item(
                        Key=bestline_job_key(course_id, hole_num, job_id),
                        UpdateExpression="SET #s = :s, #e = :e, #u = :u",
                        ExpressionAttributeNames={"#s": "status", "#e": "error", "#u": "updatedAt"},
                        ExpressionAttributeValues={
                            ":s": "failed",
                            ":e": "Bestline job timed out",
                            ":u": datetime.now(timezone.utc).isoformat(),
                        },
                    )
                    return error("Bestline job timed out", 504)
            except Exception:
                logger.exception("Failed to parse updatedAt for bestline job", extra=ctx)

        return success(
            {
                "jobId": job_id,
                "status": status or "queued",
                "updatedAt": item.get("updatedAt"),
            }
        )
    except Exception:
        logger.exception("Failed to fetch bestline job", extra=ctx)
        return error("Internal server error", 500)
