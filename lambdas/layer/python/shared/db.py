import os
from decimal import Decimal

import boto3

from shared.log import get_logger

logger = get_logger(__name__)

_table = None
_job_table = None


def get_table():
    global _table
    if _table is None:
        table_name = os.environ["TABLE_NAME"]
        logger.info("Initializing DynamoDB table: %s", table_name)
        dynamodb = boto3.resource("dynamodb")
        _table = dynamodb.Table(table_name)
    return _table


def get_job_table():
    global _job_table
    if _job_table is None:
        table_name = os.environ["JOB_TABLE_NAME"]
        logger.info("Initializing job DynamoDB table: %s", table_name)
        dynamodb = boto3.resource("dynamodb")
        _job_table = dynamodb.Table(table_name)
    return _job_table


def bestline_job_key(course_id, hole_num, job_id):
    hole_key = str(hole_num).zfill(2)
    return {
        "pk": f"COURSE#{course_id}#HOLE#{hole_key}",
        "sk": f"BESTLINE#{job_id}",
    }


def to_dynamo(obj):
    """Convert Python floats to Decimal for DynamoDB compatibility."""
    if isinstance(obj, float):
        return Decimal(str(obj))
    if isinstance(obj, dict):
        return {k: to_dynamo(v) for k, v in obj.items()}
    if isinstance(obj, list):
        return [to_dynamo(i) for i in obj]
    return obj
