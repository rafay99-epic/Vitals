import * as BunRuntime from "@effect/platform-bun/BunRuntime";
import * as Layer from "effect/Layer";

import { makeApp } from "./app.ts";
import { stdioTransport } from "./bridge/Bridge.ts";
import { configFromEnv } from "./config.ts";
import { reportExit, reportingLoggerLayer, startReporting } from "./reporting/Reporting.ts";

const config = configFromEnv(process.env);

startReporting({ enabled: process.env["VITALS_ERROR_REPORTS"] === "1", channel: config.channel, version: process.env["VITALS_VERSION"] ?? "0" });

Layer.launch(
  makeApp(config, { transport: stdioTransport }).pipe(Layer.provide(reportingLoggerLayer)),
).pipe(reportExit, BunRuntime.runMain);
