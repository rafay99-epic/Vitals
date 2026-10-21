import { Row } from "@vitals/ui";

import { isDevBuild } from "../../lib/variant";

export function DiagnosticsEntry({ onOpen }: { readonly onOpen: () => void }) {
  return isDevBuild ? <Row label="Diagnostics" detail="link, calls, frames, memory, faults" onPress={onOpen} /> : null;
}
