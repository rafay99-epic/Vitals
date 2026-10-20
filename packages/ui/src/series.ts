export interface SeriesSource {
  readonly values: () => ReadonlyArray<number>;
  readonly subscribe: (listener: () => void) => () => void;
}
