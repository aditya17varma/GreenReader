from shared.db import get_table
from shared.response import success


def handler(event, context):
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

    return success({"courses": courses})
