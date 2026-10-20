import { Canvas, Picture, Skia, createPicture } from "@shopify/react-native-skia";
import { useEffect, useState } from "react";
import { type LayoutChangeEvent, View } from "react-native";
import { useDerivedValue, useSharedValue } from "react-native-reanimated";

export interface GridSource {
  readonly rows: () => ReadonlyArray<ReadonlyArray<number>>;
  readonly subscribe: (listener: () => void) => () => void;
}

export function Heatstrip({ source, rowHeight = 7, capacity = 60 }: { readonly source: GridSource; readonly rowHeight?: number; readonly capacity?: number }) {
  const [width, setWidth] = useState(0);
  const grid = useSharedValue<ReadonlyArray<ReadonlyArray<number>>>(source.rows());
  useEffect(() => {
    grid.set(source.rows());
    return source.subscribe(() => grid.set(source.rows()));
  }, [source, grid]);

  const rowsCount = source.rows().length;
  const height = Math.max(rowsCount, 1) * (rowHeight + 1);

  const picture = useDerivedValue(() =>
    createPicture((canvas) => {
      const rows = grid.get();
      const cell = width / capacity;
      const paint = Skia.Paint();
      rows.forEach((values, row) => {
        const offset = capacity - values.length;
        values.forEach((value, column) => {
          const load = Math.min(Math.max(value, 0), 100) / 100;
          const color =
            load >= 0.85 ? [1, 0.42, 0.42] : load >= 0.6 ? [1, 0.8, 0.3] : load >= 0.25 ? [0.49, 0.77, 1] : [0.42, 0.42, 0.42];
          paint.setColor(Skia.Color(`rgba(${Math.round((color[0] ?? 0) * 255)}, ${Math.round((color[1] ?? 0) * 255)}, ${Math.round((color[2] ?? 0) * 255)}, ${0.15 + load * 0.85})`));
          canvas.drawRect(Skia.XYWHRect((offset + column) * cell, row * (rowHeight + 1), Math.max(cell - 0.5, 0.5), rowHeight), paint);
        });
      });
    }),
  );

  return (
    <View style={{ height }} onLayout={(event: LayoutChangeEvent) => setWidth(event.nativeEvent.layout.width)}>
      {width === 0 ? null : (
        <Canvas style={{ width, height }}>
          <Picture picture={picture} />
        </Canvas>
      )}
    </View>
  );
}
