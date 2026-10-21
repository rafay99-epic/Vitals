import * as BunRuntime from "@effect/platform-bun/BunRuntime";
import * as Layer from "effect/Layer";

import { makeApp } from "./app.ts";
import { stdioTransport } from "./bridge/Bridge.ts";
import { configFromEnv } from "./config.ts";

const config = configFromEnv(process.env);

Layer.launch(
  makeApp(config, { transport: stdioTransport }),
).pipe(BunRuntime.runMain);
