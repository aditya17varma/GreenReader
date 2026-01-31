import { Construct } from "constructs";
import {
  Distribution,
  ViewerProtocolPolicy,
  CachePolicy,
} from "aws-cdk-lib/aws-cloudfront";
import { S3BucketOrigin } from "aws-cdk-lib/aws-cloudfront-origins";
import { Bucket } from "aws-cdk-lib/aws-s3";
import { CDN_COMMENT } from "./constants";

export interface CdnConstructProps {
  bucket: Bucket;
}

export class CdnConstruct extends Construct {
  public readonly distribution: Distribution;

  constructor(scope: Construct, id: string, props: CdnConstructProps) {
    super(scope, id);

    this.distribution = new Distribution(this, "Distribution", {
      comment: CDN_COMMENT,
      defaultBehavior: {
        origin: S3BucketOrigin.withOriginAccessControl(props.bucket),
        viewerProtocolPolicy: ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
        cachePolicy: CachePolicy.CACHING_OPTIMIZED,
      },
    });
  }
}
