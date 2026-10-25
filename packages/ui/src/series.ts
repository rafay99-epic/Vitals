export interface SeriesSource {
  readonly values: () => ReadonlyArray<number>;
  readonly subscribe: (listener: () => void) => () => void;
}

export const EMPTY_SERIES: SeriesSource = {
  values: () => [],
  subscribe: () => () => undefined,
};

export interface GridSource {
  readonly rows: () => ReadonlyArray<ReadonlyArray<number>>;
  readonly subscribe: (listener: () => void) => () => void;
}
