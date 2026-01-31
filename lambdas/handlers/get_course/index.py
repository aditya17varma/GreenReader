from shared.db import get_table
from shared.response import error, success


def handler(event, context):
    course_id = event["pathParameters"]["courseId"]
    table = get_table()

    result = table.query(
        KeyConditionExpression="pk = :pk",
        ExpressionAttributeValues={":pk": f"COURSE#{course_id}"},
    )

    items = result.get("Items", [])
    if not items:
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
        return error("Course not found", 404)

    course["holes"] = sorted(holes, key=lambda h: h["holeNum"])
    return success({"course": course})
