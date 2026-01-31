import { join } from "path";
import { Construct } from "constructs";
import {
  Function as LambdaFunction,
  Runtime,
  Code,
  LayerVersion,
} from "aws-cdk-lib/aws-lambda";
import {
  RestApi,
  Cors,
  LambdaIntegration,
} from "aws-cdk-lib/aws-apigateway";
import { Bucket } from "aws-cdk-lib/aws-s3";
import { Table } from "aws-cdk-lib/aws-dynamodb";
import { Distribution } from "aws-cdk-lib/aws-cloudfront";
import { API_NAME, LAYER_NAME, LAMBDA_NAMES } from "./constants";

export interface ApiConstructProps {
  bucket: Bucket;
  table: Table;
  distribution: Distribution;
}

export class ApiConstruct extends Construct {
  public readonly api: RestApi;

  constructor(scope: Construct, id: string, props: ApiConstructProps) {
    super(scope, id);

    // Shared Lambda layer (db, s3, response helpers)
    const sharedLayer = new LayerVersion(this, "SharedLayer", {
      layerVersionName: LAYER_NAME,
      code: Code.fromAsset(join(__dirname, "../../lambdas/layer")),
      compatibleRuntimes: [Runtime.PYTHON_3_12],
      description: "Shared utilities for GreenReader lambdas",
    });

    const commonEnv = {
      TABLE_NAME: props.table.tableName,
      BUCKET_NAME: props.bucket.bucketName,
      CDN_DOMAIN: props.distribution.distributionDomainName,
    };

    // Helper to create a Lambda function wired to DynamoDB + S3
    const makeFn = (name: string, functionName: string, handlerDir: string): LambdaFunction => {
      const fn = new LambdaFunction(this, name, {
        functionName,
        runtime: Runtime.PYTHON_3_12,
        handler: "index.handler",
        code: Code.fromAsset(
          join(__dirname, `../../lambdas/handlers/${handlerDir}`)
        ),
        layers: [sharedLayer],
        environment: commonEnv,
      });
      props.table.grantReadWriteData(fn);
      props.bucket.grantReadWrite(fn);
      return fn;
    };

    // Lambda functions
    const listCoursesFn = makeFn("ListCourses", LAMBDA_NAMES.listCourses, "list_courses");
    const createCourseFn = makeFn("CreateCourse", LAMBDA_NAMES.createCourse, "create_course");
    const getCourseFn = makeFn("GetCourse", LAMBDA_NAMES.getCourse, "get_course");
    const getHoleFn = makeFn("GetHole", LAMBDA_NAMES.getHole, "get_hole");
    const registerHoleFn = makeFn("RegisterHole", LAMBDA_NAMES.registerHole, "register_hole");
    const updateHoleFn = makeFn("UpdateHole", LAMBDA_NAMES.updateHole, "update_hole");

    // API Gateway
    this.api = new RestApi(this, "GreenReaderApi", {
      restApiName: API_NAME,
      defaultCorsPreflightOptions: {
        allowOrigins: Cors.ALL_ORIGINS,
        allowMethods: Cors.ALL_METHODS,
      },
    });

    // Routes
    const courses = this.api.root.addResource("courses");
    courses.addMethod("GET", new LambdaIntegration(listCoursesFn));
    courses.addMethod("POST", new LambdaIntegration(createCourseFn));

    const course = courses.addResource("{courseId}");
    course.addMethod("GET", new LambdaIntegration(getCourseFn));

    const holes = course.addResource("holes");
    const hole = holes.addResource("{holeNum}");
    hole.addMethod("GET", new LambdaIntegration(getHoleFn));
    hole.addMethod("POST", new LambdaIntegration(registerHoleFn));
    hole.addMethod("PUT", new LambdaIntegration(updateHoleFn));
  }
}
