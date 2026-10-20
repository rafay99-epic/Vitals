import { LoadSkiaWeb } from "@shopify/react-native-skia/lib/module/web";
import { registerRootComponent } from "expo";

LoadSkiaWeb({ locateFile: (file: string) => `/${file}` }).then(async () => {
  const { Root } = await import("./src/Root.tsx");
  registerRootComponent(Root);
});
