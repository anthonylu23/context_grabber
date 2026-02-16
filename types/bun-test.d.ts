declare module "bun:test" {
  type TestHandler = () => void | Promise<void>;

  interface Matchers {
    toBe(expected: unknown): void;
    toEqual(expected: unknown): void;
    toBeUndefined(): void;
    toContain(expected: unknown): void;
    toThrow(expected?: unknown): void;
    toHaveLength(expected: number): void;
    not: Matchers;
  }

  export function describe(name: string, fn: TestHandler): void;
  export function it(name: string, fn: TestHandler): void;
  export function expect(actual: unknown): Matchers;
  export function beforeEach(fn: TestHandler): void;
  export function afterEach(fn: TestHandler): void;
}
