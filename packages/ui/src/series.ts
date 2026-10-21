export interface SeriesSource {
  readonly values: () => ReadonlyArray<number>;
  readonly subscribe: (listener: () => void) => () => void;
}

export interface GridSource {
  readonly rows: () => ReadonlyArray<ReadonlyArray<number>>;
  readonly subscribe: (listener: () => void) => () => void;
}
