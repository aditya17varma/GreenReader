import { Construct } from "constructs";
import { RemovalPolicy, CfnOutput } from "aws-cdk-lib";
import { Bucket, BlockPublicAccess } from "aws-cdk-lib/aws-s3";
import {
  Distribution,
  ViewerProtocolPolicy,
  CachePolicy,
  Function as CloudFrontFunction,
  FunctionCode,
  FunctionEventType,
} from "aws-cdk-lib/aws-cloudfront";
import { S3BucketOrigin } from "aws-cdk-lib/aws-cloudfront-origins";
import { FRONTEND_BUCKET_NAME, FRONTEND_CDN_COMMENT } from "./constants";

// CloudFront Function to set Content-Encoding header for Brotli-compressed files
const BROTLI_RESPONSE_FUNCTION = `
function handler(event) {
  var response = event.response;
  var request = event.request;
  var uri = request.uri;

  // Set Content-Encoding: br for .br files
  if (uri.endsWith('.br')) {
    response.headers['content-encoding'] = { value: 'br' };

    // Set appropriate Content-Type based on the actual file type
    if (uri.endsWith('.js.br')) {
      response.headers['content-type'] = { value: 'application/javascript' };
    } else if (uri.endsWith('.wasm.br')) {
      response.headers['content-type'] = { value: 'application/wasm' };
    } else if (uri.endsWith('.data.br')) {
      response.headers['content-type'] = { value: 'application/octet-stream' };
    }
  }

  return response;
}
`;

export class FrontendConstruct extends Construct {
  public readonly bucket: Bucket;
  public readonly distribution: Distribution;

  constructor(scope: Construct, id: string) {
    super(scope, id);

    // S3 bucket for static frontend files
    this.bucket = new Bucket(this, "FrontendBucket", {
      bucketName: FRONTEND_BUCKET_NAME,
      removalPolicy: RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      blockPublicAccess: BlockPublicAccess.BLOCK_ALL,
    });

    // CloudFront Function to handle Brotli Content-Encoding
    const brotliFunction = new CloudFrontFunction(this, "BrotliEncodingFunction", {
      code: FunctionCode.fromInline(BROTLI_RESPONSE_FUNCTION),
      comment: "Set Content-Encoding: br for Brotli-compressed Unity files",
    });

    // CloudFront distribution
    this.distribution = new Distribution(this, "FrontendDistribution", {
      comment: FRONTEND_CDN_COMMENT,
      defaultBehavior: {
        origin: S3BucketOrigin.withOriginAccessControl(this.bucket),
        viewerProtocolPolicy: ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
        cachePolicy: CachePolicy.CACHING_OPTIMIZED,
        functionAssociations: [
          {
            function: brotliFunction,
            eventType: FunctionEventType.VIEWER_RESPONSE,
          },
        ],
      },
      defaultRootObject: "index.html",
      // Handle SPA routing - return index.html for 404s
      errorResponses: [
        {
          httpStatus: 403,
          responseHttpStatus: 200,
          responsePagePath: "/index.html",
        },
        {
          httpStatus: 404,
          responseHttpStatus: 200,
          responsePagePath: "/index.html",
        },
      ],
    });

    new CfnOutput(this, "FrontendUrl", {
      value: `https://${this.distribution.distributionDomainName}`,
      description: "Frontend URL",
    });

    new CfnOutput(this, "FrontendBucketName", {
      value: this.bucket.bucketName,
      description: "Frontend S3 bucket for deployment",
    });
  }
}
