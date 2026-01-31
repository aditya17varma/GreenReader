import json

from shared.db import get_table, to_dynamo
from shared.response import error, success
from shared.s3 import presigned_upload_url

SOURCE_FILES = {
    "image.png": "image/png",
    "boundary.json": "application/json",
    "contours.json": "application/json",
}

PROCESSED_FILES = {
    "heightfield.json": "application/json",
    "heightfield.bin": "application/octet-stream",
}


def handler(event, context):
    course_id = event["pathParameters"]["courseId"]
    hole_num = event["pathParameters"]["holeNum"]

    try:
        body = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        body = {}

    table = get_table()
    s3_prefix = f"{course_id}/{hole_num}"

    item = {
        "pk": f"COURSE#{course_id}",
        "sk": f"HOLE#{hole_num.zfill(2)}",
        "courseId": course_id,
        "holeNum": int(hole_num),
        "hasSource": False,
        "hasProcessed": False,
    }

    for field in ("greenWidthFt", "greenHeightFt", "holeXzFt"):
        if body.get(field) is not None:
            item[field] = body[field]

    table.put_item(Item=to_dynamo(item))

    upload_urls = {
        "source": {
            name: presigned_upload_url(
                f"{s3_prefix}/source/{name}", content_type=ct
            )
            for name, ct in SOURCE_FILES.items()
        },
        "processed": {
            name: presigned_upload_url(
                f"{s3_prefix}/processed/{name}", content_type=ct
            )
            for name, ct in PROCESSED_FILES.items()
        },
    }

    return success({"holeNum": int(hole_num), "uploadUrls": upload_urls}, status_code=201)
