import json

from shared.db import get_table, to_dynamo
from shared.log import get_logger
from shared.response import error, success

logger = get_logger(__name__)


def handler(event, context):
    logger.info("Creating course")

    try:
        try:
            body = json.loads(event.get("body", "{}"))
        except json.JSONDecodeError:
            return error("Invalid JSON body")

        course_id = body.get("id")
        name = body.get("name")
        if not course_id or not name:
            return error("Missing required fields: id, name")

        ctx = {"course_id": course_id}
        logger.info("Course payload parsed", extra=ctx)

        table = get_table()

        item = {
            "pk": f"COURSE#{course_id}",
            "sk": "META",
            "gsi1pk": "COURSES",
            "gsi1sk": course_id,
            "courseId": course_id,
            "name": name,
        }

        # Optional fields
        for field in ("city", "state", "location", "numHoles"):
            if body.get(field) is not None:
                item[field] = body[field]

        item.setdefault("numHoles", 18)

        table.put_item(Item=to_dynamo(item))

        logger.info("Course created", extra=ctx)
        return success(
            {
                "course": {
                    "id": course_id,
                    "name": name,
                    "city": item.get("city"),
                    "state": item.get("state"),
                    "location": item.get("location"),
                    "numHoles": item.get("numHoles"),
                }
            },
            status_code=201,
        )
    except Exception:
        logger.exception("Failed to create course")
        return error("Internal server error", 500)
