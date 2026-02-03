import json

from shared.db import get_table, to_dynamo
from shared.log import get_logger
from shared.response import error, success

logger = get_logger(__name__)

ALLOWED_FIELDS = {
    "hasSource": ":src",
    "hasProcessed": ":proc",
    "greenWidthFt": ":w",
    "greenHeightFt": ":h",
    "holeXzFt": ":hole",
}


def handler(event, context):
    course_id = event["pathParameters"]["courseId"]
    hole_num = event["pathParameters"]["holeNum"]
    ctx = {"course_id": course_id, "hole_num": hole_num}
    logger.info("Updating hole", extra=ctx)

    try:
        try:
            body = json.loads(event.get("body") or "{}")
        except json.JSONDecodeError:
            return error("Invalid JSON body")

        if not body:
            return error("Request body is empty")

        # Build update expression from provided fields
        set_parts = []
        expr_values = {}

        for field, placeholder in ALLOWED_FIELDS.items():
            if field in body:
                set_parts.append(f"{field} = {placeholder}")
                expr_values[placeholder] = body[field]

        if not set_parts:
            return error("No valid fields to update")

        table = get_table()

        result = table.update_item(
            Key={
                "pk": f"COURSE#{course_id}",
                "sk": f"HOLE#{hole_num.zfill(2)}",
            },
            UpdateExpression="SET " + ", ".join(set_parts),
            ExpressionAttributeValues=to_dynamo(expr_values),
            ReturnValues="ALL_NEW",
        )

        item = result.get("Attributes", {})

        logger.info("Hole updated", extra=ctx)
        return success(
            {
                "hole": {
                    "courseId": course_id,
                    "holeNum": int(hole_num),
                    "hasSource": item.get("hasSource", False),
                    "hasProcessed": item.get("hasProcessed", False),
                    "greenWidthFt": item.get("greenWidthFt"),
                    "greenHeightFt": item.get("greenHeightFt"),
                    "holeXzFt": item.get("holeXzFt"),
                }
            }
        )
    except Exception:
        logger.exception("Failed to update hole", extra=ctx)
        return error("Internal server error", 500)
