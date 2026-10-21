export interface ReadableStore<T> {
  readonly get: () => T;
  readonly subscribe: (listener: () => void) => () => void;
}

export class Store<T> implements ReadableStore<T> {
  private value: T;
  private readonly listeners = new Set<() => void>();

  constructor(initial: T) {
    this.value = initial;
  }

  readonly get = (): T => this.value;

  readonly subscribe = (listener: () => void): (() => void) => {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  };

  set(next: T): void {
    if (Object.is(next, this.value)) return;
    this.value = next;
    for (const listener of this.listeners) listener();
  }

  update(change: (current: T) => T): void {
    this.set(change(this.value));
  }
}
