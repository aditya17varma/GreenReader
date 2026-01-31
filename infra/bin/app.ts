#!/usr/bin/env node
import { App } from "aws-cdk-lib";
import { GreenReaderStack } from "../lib/greenreader-stack";

const app = new App();

new GreenReaderStack(app, "GreenReaderStack", {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
});
