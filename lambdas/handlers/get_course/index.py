from shared.db import get_table
from shared.log import get_logger
from shared.response import error, success

logger = get_logger(__name__)


def handler(event, context):
    course_id = event["pathParameters"]["courseId"]
    ctx = {"course_id": course_id}
    logger.info("Getting course", extra=ctx)

    try:
        table = get_table()

        result = table.query(
            KeyConditionExpression="pk = :pk",
            ExpressionAttributeValues={":pk": f"COURSE#{course_id}"},
        )

        items = result.get("Items", [])
        if not items:
            logger.info("Course not found", extra=ctx)
            return error("Course not found", 404)

        course = None
        holes = []

        for item in items:
            if item["sk"] == "META":
                course = {
                    "id": item["courseId"],
                    "name": item["name"],
                    "city": item.get("city"),
                    "state": item.get("state"),
                    "location": item.get("location"),
                    "numHoles": item.get("numHoles"),
                }
            elif item["sk"].startswith("HOLE#"):
                holes.append(
                    {
                        "holeNum": item["holeNum"],
                        "greenWidthFt": item.get("greenWidthFt"),
                        "greenHeightFt": item.get("greenHeightFt"),
                        "hasSource": item.get("hasSource", False),
                        "hasProcessed": item.get("hasProcessed", False),
                    }
                )

        if course is None:
            logger.info("Course META not found", extra=ctx)
            return error("Course not found", 404)

        course["holes"] = sorted(holes, key=lambda h: h["holeNum"])
        logger.info("Course retrieved with %d holes", len(holes), extra=ctx)
        return success({"course": course})
    except Exception:
        logger.exception("Failed to get course", extra=ctx)
        return error("Internal server error", 500)
