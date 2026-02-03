import { join } from "path";
import { Duration } from "aws-cdk-lib";
import { Construct } from "constructs";
import {
  Function as LambdaFunction,
  Runtime,
  Code,
  LayerVersion,
  Tracing,
  Architecture,
} from "aws-cdk-lib/aws-lambda";
import {
  RestApi,
  Cors,
  LambdaIntegration,
  AccessLogFormat,
  LogGroupLogDestination,
} from "aws-cdk-lib/aws-apigateway";
import { LogGroup, RetentionDays } from "aws-cdk-lib/aws-logs";
import { Bucket } from "aws-cdk-lib/aws-s3";
import { Table } from "aws-cdk-lib/aws-dynamodb";
import { Distribution } from "aws-cdk-lib/aws-cloudfront";
import { API_NAME, LAYER_NAME, LAMBDA_NAMES } from "./constants";

export interface ApiConstructProps {
  bucket: Bucket;
  table: Table;
  jobTable: Table;
  distribution: Distribution;
}

// Project root relative to this file (infra/lib/) -> ../../
const PROJECT_ROOT = join(__dirname, "../..");

export class ApiConstruct extends Construct {
  public readonly api: RestApi;

  constructor(scope: Construct, id: string, props: ApiConstructProps) {
    super(scope, id);

    // Shared Lambda layer (db, s3, response helpers)
    const sharedLayer = new LayerVersion(this, "SharedLayer", {
      layerVersionName: LAYER_NAME,
      code: Code.fromAsset(join(PROJECT_ROOT, "lambdas/layer")),
      compatibleRuntimes: [Runtime.PYTHON_3_12],
      description: "Shared utilities for GreenReader lambdas",
    });

    const commonEnv = {
      TABLE_NAME: props.table.tableName,
      JOB_TABLE_NAME: props.jobTable.tableName,
      BUCKET_NAME: props.bucket.bucketName,
      CDN_DOMAIN: props.distribution.distributionDomainName,
      LOG_LEVEL: "INFO",
    };

    // Helper to create a lightweight Lambda (API/CRUD handlers)
    const makeFn = (name: string, functionName: string, handlerDir: string): LambdaFunction => {
      const fn = new LambdaFunction(this, name, {
        functionName,
        runtime: Runtime.PYTHON_3_12,
        handler: "index.handler",
        code: Code.fromAsset(
          join(PROJECT_ROOT, `lambdas/handlers/${handlerDir}`)
        ),
        layers: [sharedLayer],
        environment: commonEnv,
        architecture: Architecture.ARM_64,
        timeout: Duration.seconds(10),
        logGroup: new LogGroup(this, `${name}Logs`, {
          retention: RetentionDays.TWO_WEEKS,
        }),
        tracing: Tracing.ACTIVE,
      });
      props.table.grantReadWriteData(fn);
      props.bucket.grantReadWrite(fn);
      return fn;
    };

    // CRUD Lambda functions
    const listCoursesFn = makeFn("ListCourses", LAMBDA_NAMES.listCourses, "list_courses");
    const createCourseFn = makeFn("CreateCourse", LAMBDA_NAMES.createCourse, "create_course");
    const getCourseFn = makeFn("GetCourse", LAMBDA_NAMES.getCourse, "get_course");
    const getHoleFn = makeFn("GetHole", LAMBDA_NAMES.getHole, "get_hole");
    const registerHoleFn = makeFn("RegisterHole", LAMBDA_NAMES.registerHole, "register_hole");
    const updateHoleFn = makeFn("UpdateHole", LAMBDA_NAMES.updateHole, "update_hole");
    // Helper for thin bestline API handlers (not created via makeFn — no catalog table access needed)
    const makeBestlineFn = (name: string, functionName: string, handlerDir: string): LambdaFunction => {
      const fn = new LambdaFunction(this, name, {
        functionName,
        runtime: Runtime.PYTHON_3_12,
        handler: "index.handler",
        code: Code.fromAsset(
          join(PROJECT_ROOT, `lambdas/handlers/${handlerDir}`)
        ),
        layers: [sharedLayer],
        environment: commonEnv,
        architecture: Architecture.ARM_64,
        timeout: Duration.seconds(10),
        logGroup: new LogGroup(this, `${name}Logs`, {
          retention: RetentionDays.TWO_WEEKS,
        }),
        tracing: Tracing.ACTIVE,
      });
      return fn;
    };

    const submitBestlineFn = makeBestlineFn("SubmitBestline", LAMBDA_NAMES.submitBestline, "submit_bestline");
    props.jobTable.grantReadWriteData(submitBestlineFn);
    props.bucket.grantRead(submitBestlineFn);

    const getBestlineFn = makeBestlineFn("GetBestline", LAMBDA_NAMES.getBestline, "get_bestline");
    props.jobTable.grantReadWriteData(getBestlineFn);
    props.bucket.grantRead(getBestlineFn);

    // Compute Lambda — bundles numpy + backend physics/terrain modules via Docker
    const computeBestlineFn = new LambdaFunction(this, "ComputeBestline", {
      functionName: LAMBDA_NAMES.computeBestline,
      runtime: Runtime.PYTHON_3_12,
      handler: "index.handler",
      code: Code.fromAsset(PROJECT_ROOT, {
        bundling: {
          image: Runtime.PYTHON_3_12.bundlingImage,
          command: [
            "bash", "-c",
            [
              "pip install numpy -t /asset-output",
              "cp lambdas/handlers/compute_bestline/index.py /asset-output/",
              "mkdir -p /asset-output/terrain /asset-output/physics",
              "cp backend/terrain/__init__.py backend/terrain/heightmap.py backend/terrain/green.py /asset-output/terrain/",
              "cp backend/physics/__init__.py backend/physics/ball_roll_stimp.py backend/physics/best_line_refine.py /asset-output/physics/",
            ].join(" && "),
          ],
        },
      }),
      layers: [sharedLayer],
      environment: commonEnv,
      architecture: Architecture.ARM_64,
      memorySize: 3008,
      timeout: Duration.seconds(180),
      logGroup: new LogGroup(this, "ComputeBestlineLogs", {
        retention: RetentionDays.TWO_WEEKS,
      }),
      tracing: Tracing.ACTIVE,
    });
    props.bucket.grantReadWrite(computeBestlineFn);
    props.jobTable.grantReadWriteData(computeBestlineFn);

    computeBestlineFn.grantInvoke(submitBestlineFn);

    submitBestlineFn.addEnvironment("COMPUTE_BESTLINE_FUNCTION", computeBestlineFn.functionName);

    // API Gateway access logs
    const apiLogGroup = new LogGroup(this, "ApiAccessLogs", {
      retention: RetentionDays.TWO_WEEKS,
    });

    // API Gateway
    this.api = new RestApi(this, "GreenReaderApi", {
      restApiName: API_NAME,
      defaultCorsPreflightOptions: {
        allowOrigins: Cors.ALL_ORIGINS,
        allowMethods: Cors.ALL_METHODS,
      },
      deployOptions: {
        accessLogDestination: new LogGroupLogDestination(apiLogGroup),
        accessLogFormat: AccessLogFormat.jsonWithStandardFields(),
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

    const bestline = hole.addResource("bestline");
    bestline.addMethod("POST", new LambdaIntegration(submitBestlineFn));
    const bestlineJob = bestline.addResource("{jobId}");
    bestlineJob.addMethod("GET", new LambdaIntegration(getBestlineFn));
  }
}
