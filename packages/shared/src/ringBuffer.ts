export class RingBuffer {
  readonly capacity: number;
  private readonly values: Float64Array;
  private start = 0;
  private count = 0;

  constructor(capacity: number) {
    this.capacity = capacity;
    this.values = new Float64Array(capacity);
  }

  get length(): number {
    return this.count;
  }

  push(value: number): void {
    const index = (this.start + this.count) % this.capacity;
    this.values[index] = value;
    if (this.count < this.capacity) this.count += 1;
    else this.start = (this.start + 1) % this.capacity;
  }

  at(index: number): number {
    return this.values[(this.start + index) % this.capacity] ?? Number.NaN;
  }

  toArray(): Array<number> {
    return Array.from({ length: this.count }, (_, index) => this.at(index));
  }
}
