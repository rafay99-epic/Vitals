import * as BunRuntime from "@effect/platform-bun/BunRuntime";
import * as Layer from "effect/Layer";

import { makeApp } from "./app.ts";
import { stdioTransport } from "./bridge/Bridge.ts";
import { configFromEnv } from "./config.ts";
import { expoSender } from "./guard/AlertDispatcher.ts";

const config = configFromEnv(process.env);

Layer.launch(
  makeApp(config, {
    transport: stdioTransport,
    push: expoSender(process.env["VITALS_EXPO_ACCESS_TOKEN"] ?? null),
  }),
).pipe(BunRuntime.runMain);
