from shared.db import get_table
from shared.log import get_logger
from shared.response import error, success

logger = get_logger(__name__)


def handler(event, context):
    logger.info("Listing courses")

    try:
        table = get_table()

        result = table.query(
            IndexName="gsi1",
            KeyConditionExpression="gsi1pk = :pk",
            ExpressionAttributeValues={":pk": "COURSES"},
        )

        courses = []
        for item in result.get("Items", []):
            courses.append(
                {
                    "id": item["courseId"],
                    "name": item["name"],
                    "city": item.get("city"),
                    "state": item.get("state"),
                    "location": item.get("location"),
                    "numHoles": item.get("numHoles"),
                }
            )

        logger.info("Listed %d courses", len(courses))
        return success({"courses": courses})
    except Exception:
        logger.exception("Failed to list courses")
        return error("Internal server error", 500)
