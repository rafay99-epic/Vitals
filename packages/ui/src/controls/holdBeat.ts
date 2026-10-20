export const beatPoints = (width: number, height: number): ReadonlyArray<readonly [number, number]> => [
  [0, height * 0.62],
  [width * 0.25, height * 0.62],
  [width * 0.29, height * 0.77],
  [width * 0.34, height * 0.25],
  [width * 0.38, height * 0.62],
  [width, height * 0.62],
];
