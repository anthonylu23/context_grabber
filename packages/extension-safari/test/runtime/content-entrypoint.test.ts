import { describe, expect, it } from "bun:test";
import {
  CAPTURE_ACTIVE_TAB_MESSAGE_TYPE,
  registerSafariContentCaptureListener,
} from "../../src/runtime/index.js";

const createFakeDocument = (): Document => {
  const headings = [
    {
      tagName: "H1",
      textContent: "Heading 1",
    },
  ];

  const links = [
    {
      textContent: "Docs",
      href: "https://example.com/docs",
    },
  ];

  return {
    title: "Example Title",
    location: { href: "https://example.com" } as Location,
    body: { innerText: "Paragraph one.\n\nParagraph two." } as HTMLElement,
    querySelector: () => null,
    querySelectorAll: (selector: string) => {
      if (selector === "h1, h2, h3, h4, h5, h6") {
        return headings as unknown as NodeListOf<Element>;
      }

      if (selector === "a[href]") {
        return links as unknown as NodeListOf<HTMLAnchorElement>;
      }

      return [] as unknown as NodeListOf<Element>;
    },
    documentElement: { lang: "en-US" } as HTMLElement,
  } as unknown as Document;
};

describe("safari runtime content entrypoint", () => {
  it("returns page snapshot for capture messages", async () => {
    let listener: ((message: unknown, sender: unknown) => unknown | Promise<unknown>) | undefined;

    const browser = {
      runtime: {
        onMessage: {
          addListener(next: (message: unknown, sender: unknown) => unknown | Promise<unknown>) {
            listener = next;
          },
        },
      },
    };

    registerSafariContentCaptureListener(browser, createFakeDocument);
    if (!listener) {
      throw new Error("onMessage listener was not registered.");
    }

    const response = await listener(
      {
        type: CAPTURE_ACTIVE_TAB_MESSAGE_TYPE,
        includeSelectionText: true,
      },
      {},
    );

    if (typeof response !== "object" || response === null) {
      throw new Error("Expected snapshot response object.");
    }

    expect((response as { url?: string }).url).toBe("https://example.com");
    expect((response as { title?: string }).title).toBe("Example Title");
  });

  it("ignores unrelated runtime messages", async () => {
    let listener: ((message: unknown, sender: unknown) => unknown | Promise<unknown>) | undefined;

    const browser = {
      runtime: {
        onMessage: {
          addListener(next: (message: unknown, sender: unknown) => unknown | Promise<unknown>) {
            listener = next;
          },
        },
      },
    };

    registerSafariContentCaptureListener(browser, createFakeDocument);
    if (!listener) {
      throw new Error("onMessage listener was not registered.");
    }

    const response = await listener({ type: "other" }, {});
    expect(response).toBe(undefined);
  });
});
