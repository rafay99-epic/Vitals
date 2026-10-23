import { Row } from "@vitals/ui";

import { isStoreBuild } from "../../lib/variant";

export function DiagnosticsEntry({ onOpen }: { readonly onOpen: () => void }) {
  return isStoreBuild ? null : <Row label="Diagnostics" detail="link, calls, frames, memory, faults" onPress={onOpen} />;
}
