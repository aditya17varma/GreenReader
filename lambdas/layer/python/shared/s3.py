import os

import boto3

from shared.log import get_logger

logger = get_logger(__name__)

_client = None


def get_client():
    global _client
    if _client is None:
        _client = boto3.client("s3")
    return _client


def get_bucket():
    return os.environ["BUCKET_NAME"]


def get_cdn_domain():
    return os.environ["CDN_DOMAIN"]


def presigned_upload_url(key, expires_in=3600, content_type=None):
    """Generate a pre-signed PUT URL for uploading to S3."""
    logger.info("Generating presigned URL for key: %s", key)
    params = {"Bucket": get_bucket(), "Key": key}
    if content_type:
        params["ContentType"] = content_type
    return get_client().generate_presigned_url(
        "put_object", Params=params, ExpiresIn=expires_in
    )


def cdn_url(key):
    """Build a CloudFront URL for a given S3 key."""
    return f"https://{get_cdn_domain()}/{key}"
