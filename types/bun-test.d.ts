declare module "bun:test" {
  type TestHandler = () => void | Promise<void>;

  interface Matchers {
    toBe(expected: unknown): void;
    toEqual(expected: unknown): void;
    toBeUndefined(): void;
    toContain(expected: unknown): void;
    toThrow(expected?: unknown): void;
  }

  export function describe(name: string, fn: TestHandler): void;
  export function it(name: string, fn: TestHandler): void;
  export function expect(actual: unknown): Matchers;
}
