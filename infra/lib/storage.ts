import { Construct } from "constructs";
import { RemovalPolicy } from "aws-cdk-lib";
import {
  Bucket,
  BlockPublicAccess,
  HttpMethods,
  type CorsRule,
} from "aws-cdk-lib/aws-s3";
import {
  Table,
  AttributeType,
  BillingMode,
} from "aws-cdk-lib/aws-dynamodb";
import { BUCKET_NAME, TABLE_NAME } from "./constants";

export class StorageConstruct extends Construct {
  public readonly bucket: Bucket;
  public readonly table: Table;

  constructor(scope: Construct, id: string) {
    super(scope, id);

    this.bucket = new Bucket(this, "DataBucket", {
      bucketName: BUCKET_NAME,
      removalPolicy: RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      blockPublicAccess: BlockPublicAccess.BLOCK_ALL,
      cors: [
        {
          allowedMethods: [HttpMethods.PUT, HttpMethods.GET],
          allowedOrigins: ["*"],
          allowedHeaders: ["*"],
        } satisfies CorsRule,
      ],
    });

    this.table = new Table(this, "CatalogTable", {
      tableName: TABLE_NAME,
      partitionKey: { name: "pk", type: AttributeType.STRING },
      sortKey: { name: "sk", type: AttributeType.STRING },
      billingMode: BillingMode.PAY_PER_REQUEST,
      removalPolicy: RemovalPolicy.DESTROY,
    });

    this.table.addGlobalSecondaryIndex({
      indexName: "gsi1",
      partitionKey: { name: "gsi1pk", type: AttributeType.STRING },
      sortKey: { name: "gsi1sk", type: AttributeType.STRING },
    });
  }
}
