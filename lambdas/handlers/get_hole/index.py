from shared.db import get_table
from shared.response import error, success
from shared.s3 import cdn_url

SOURCE_FILES = ["image.png", "boundary.json", "contours.json"]
PROCESSED_FILES = ["heightfield.json", "heightfield.bin", "bestline.json"]


def handler(event, context):
    course_id = event["pathParameters"]["courseId"]
    hole_num = event["pathParameters"]["holeNum"]
    table = get_table()

    result = table.get_item(
        Key={
            "pk": f"COURSE#{course_id}",
            "sk": f"HOLE#{hole_num.zfill(2)}",
        }
    )

    item = result.get("Item")
    if not item:
        return error("Hole not found", 404)

    s3_prefix = f"{course_id}/{hole_num}"

    hole = {
        "courseId": course_id,
        "holeNum": int(hole_num),
        "greenWidthFt": item.get("greenWidthFt"),
        "greenHeightFt": item.get("greenHeightFt"),
        "holeXzFt": item.get("holeXzFt"),
        "hasSource": item.get("hasSource", False),
        "hasProcessed": item.get("hasProcessed", False),
    }

    if item.get("hasSource"):
        hole["sourceUrls"] = {
            f: cdn_url(f"{s3_prefix}/source/{f}") for f in SOURCE_FILES
        }

    if item.get("hasProcessed"):
        hole["processedUrls"] = {
            f: cdn_url(f"{s3_prefix}/processed/{f}") for f in PROCESSED_FILES
        }

    return success({"hole": hole})
