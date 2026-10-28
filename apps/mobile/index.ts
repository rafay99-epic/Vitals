// First, so Sentry is running before the app's modules load.
import "./src/lib/reporting.ts";

import { registerRootComponent } from "expo";

import { Root } from "./src/Root.tsx";

registerRootComponent(Root);
