import { Button, Sans } from "@vitals/ui";
import { CameraView, useCameraPermissions } from "expo-camera";
import { View } from "react-native";

export function QrScanner({ onCode }: { readonly onCode: (value: string) => void }) {
  const [permission, request] = useCameraPermissions();
  if (permission === null) return null;
  if (!permission.granted) {
    return (
      <View className="flex-1 items-center justify-center gap-4 px-12">
        <Sans tone="ink2" className="text-center">Vitals needs the camera to read the pairing code.</Sans>
        <Button label="Allow camera" variant="line" onPress={() => void request()} />
      </View>
    );
  }
  return (
    <CameraView style={{ flex: 1 }} facing="back" barcodeScannerSettings={{ barcodeTypes: ["qr"] }} onBarcodeScanned={({ data }) => onCode(data)} />
  );
}
