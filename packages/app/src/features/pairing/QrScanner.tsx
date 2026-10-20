import { CameraView, useCameraPermissions } from "expo-camera";
import { TextButton } from "@vitals/ui";
import { Text, View } from "react-native";

export function QrScanner({ onCode }: { readonly onCode: (value: string) => void }) {
  const [permission, request] = useCameraPermissions();
  if (permission === null) return null;
  if (!permission.granted) {
    return (
      <View>
        <Text className="mb-3 text-[15px] text-dim">Vitals needs the camera to read the pairing code.</Text>
        <TextButton label="Allow camera" onPress={() => void request()} />
      </View>
    );
  }
  return (
    <View className="aspect-square overflow-hidden border border-line">
      <CameraView
        style={{ flex: 1 }}
        facing="back"
        barcodeScannerSettings={{ barcodeTypes: ["qr"] }}
        onBarcodeScanned={({ data }) => onCode(data)}
      />
    </View>
  );
}
