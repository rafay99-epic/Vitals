import type { Remote } from "../state/remote.ts";
import { useStore } from "../state/useStore.ts";
import { type Session, sessions } from "./session.ts";

export const useSession = (): Session => useStore(sessions.session);

export const useRemote = (): Remote => {
  const session = useSession();
  if (session.status !== "paired") throw new Error("Not paired");
  return session.remote;
};
