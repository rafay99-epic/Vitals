import { type ReactElement, useState } from "react";
import { Modal, Pressable, Text, View } from "react-native";

export interface MenuAction {
  readonly label: string;
  readonly tone?: "ink" | "bad";
  readonly onPress: () => void;
}

export interface MenuRequest {
  readonly title: string;
  readonly detail?: string;
  readonly actions: ReadonlyArray<MenuAction>;
}

export function useActionMenu(): readonly [ReactElement, (request: MenuRequest) => void] {
  const [request, setRequest] = useState<MenuRequest | null>(null);
  const close = () => setRequest(null);
  const element = (
    <Modal visible={request !== null} transparent animationType="fade" onRequestClose={close}>
      <Pressable className="flex-1 justify-end bg-canvas/70" onPress={close} accessibilityLabel="Close menu">
        <Pressable className="border-t border-line bg-canvas px-4 pb-10 pt-4" onPress={() => {}}>
          <Text className="text-lg font-semibold text-ink">{request?.title ?? ""}</Text>
          {request?.detail === undefined ? null : <Text className="mt-1 font-mono text-xs text-dim">{request.detail}</Text>}
          <View className="mt-3">
            {(request?.actions ?? []).map((action) => (
              <Pressable
                key={action.label}
                accessibilityRole="button"
                onPress={() => {
                  close();
                  action.onPress();
                }}
                className="min-h-12 justify-center border-b border-line active:bg-line"
              >
                <Text className={`text-[16px] ${action.tone === "bad" ? "text-bad" : "text-ink"}`}>{action.label}</Text>
              </Pressable>
            ))}
            <Pressable accessibilityRole="button" onPress={close} className="min-h-12 justify-center">
              <Text className="text-[16px] text-dim">Cancel</Text>
            </Pressable>
          </View>
        </Pressable>
      </Pressable>
    </Modal>
  );
  return [element, setRequest] as const;
}
