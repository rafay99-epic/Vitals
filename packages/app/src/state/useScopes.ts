import type { Scope } from "@vitals/contracts";

import { useRemote } from "../connection/useRemote.ts";
import { useStore } from "./useStore.ts";

export const useScopes = (): ReadonlyArray<Scope> => {
  const remote = useRemote();
  const state = useStore(remote.connection.state);
  return state._tag === "Ready" ? state.hello.scopes : remote.credentials.scopes;
};
