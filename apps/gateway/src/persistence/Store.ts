import type { Database } from "bun:sqlite";
import * as Context from "effect/Context";
import * as Layer from "effect/Layer";

import { RemoteStore } from "./RemoteStore.ts";

export class Store extends Context.Service<Store, RemoteStore>()("@vitals/gateway/Store") {}

export const layer = (db: Database) => Layer.sync(Store, () => new RemoteStore(db));
