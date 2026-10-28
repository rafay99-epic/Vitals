import type { NativeStackScreenProps } from "@react-navigation/native-stack";
import { BackHeader, Screen } from "@vitals/ui";

import type { RecordStackParams } from "../../navigation/types.ts";
import { UpdatesSection } from "./UpdatesSection";

type Props = NativeStackScreenProps<RecordStackParams, "Updates">;

export function UpdatesScreen({ navigation }: Props) {
  return (
    <Screen top={<BackHeader parent="Record" onBack={() => navigation.goBack()} />}>
      <UpdatesSection />
    </Screen>
  );
}
