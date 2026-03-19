#!/usr/bin/env node
import * as cdk from "aws-cdk-lib";
import { NfwLatencyBenchStack } from "../lib/nfw-latency-bench-stack";

const app = new cdk.App();
new NfwLatencyBenchStack(app, "NfwLatencyBenchStack", {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
});
