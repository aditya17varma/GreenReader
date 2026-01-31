import json

from shared.db import get_table, to_dynamo
from shared.response import error, success


def handler(event, context):
    try:
        body = json.loads(event.get("body", "{}"))
    except json.JSONDecodeError:
        return error("Invalid JSON body")

    course_id = body.get("id")
    name = body.get("name")
    if not course_id or not name:
        return error("Missing required fields: id, name")

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
