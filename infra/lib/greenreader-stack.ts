import { Stack, StackProps, CfnOutput } from "aws-cdk-lib";
import { Construct } from "constructs";
import { StorageConstruct } from "./storage";
import { CdnConstruct } from "./cdn";
import { ApiConstruct } from "./api";

export class GreenReaderStack extends Stack {
  constructor(scope: Construct, id: string, props?: StackProps) {
    super(scope, id, props);

    const storage = new StorageConstruct(this, "Storage");

    const cdn = new CdnConstruct(this, "Cdn", {
      bucket: storage.bucket,
    });

    const api = new ApiConstruct(this, "Api", {
      bucket: storage.bucket,
      table: storage.table,
      jobTable: storage.jobTable,
      distribution: cdn.distribution,
    });

    new CfnOutput(this, "ApiUrl", { value: api.api.url });
    new CfnOutput(this, "CdnDomain", {
      value: cdn.distribution.distributionDomainName,
    });
    new CfnOutput(this, "BucketName", {
      value: storage.bucket.bucketName,
    });
  }
}
