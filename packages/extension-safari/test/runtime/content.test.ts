import { describe, expect, it } from "bun:test";
import {
  capturePageSnapshotFromDocument,
  extractSafariContextFromDocument,
} from "../../src/runtime/content.js";

const createFakeDocument = (): Document => {
  const metaMap: Record<string, string> = {
    'meta[name="description"]': "Description",
    'meta[property="og:site_name"]': "Example Site",
    'meta[name="author"]': "Author",
  };

  const headings = [
    {
      tagName: "H1",
      textContent: "Heading 1",
    },
    {
      tagName: "H2",
      textContent: "Heading 2",
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
    documentElement: { lang: "en-US" } as HTMLElement,
    querySelector: (selector: string) => {
      const content = metaMap[selector];
      if (!content) {
        return null;
      }

      return {
        getAttribute: (attribute: string) => (attribute === "content" ? content : null),
      } as Element;
    },
    querySelectorAll: (selector: string) => {
      if (selector === "h1, h2, h3, h4, h5, h6") {
        return headings as unknown as NodeListOf<Element>;
      }

      if (selector === "a[href]") {
        return links as unknown as NodeListOf<HTMLAnchorElement>;
      }

      return [] as unknown as NodeListOf<Element>;
    },
  } as Document;
};

describe("safari runtime content extraction", () => {
  it("captures page snapshot from document", () => {
    const snapshot = capturePageSnapshotFromDocument(createFakeDocument(), {
      includeSelectionText: true,
      selectionProvider: () => "Selected value",
    });

    expect(snapshot.url).toBe("https://example.com");
    expect(snapshot.title).toBe("Example Title");
    expect(snapshot.metaDescription).toBe("Description");
    expect(snapshot.siteName).toBe("Example Site");
    expect(snapshot.selectionText).toBe("Selected value");
    expect((snapshot.headings ?? []).length).toBe(2);
    expect((snapshot.links ?? []).length).toBe(1);
  });

  it("produces normalized Safari extraction input", () => {
    const extraction = extractSafariContextFromDocument(createFakeDocument(), {
      includeSelectionText: false,
      selectionProvider: () => "Should not be included",
    });

    expect(extraction.url).toBe("https://example.com");
    expect(extraction.title).toBe("Example Title");
    expect(extraction.fullText).toBe("Paragraph one.\n\nParagraph two.");
    expect(extraction.selectionText).toBe(undefined);
    expect((extraction.headings ?? []).length).toBe(2);
    expect((extraction.links ?? []).length).toBe(1);
  });

  it("does not persist null selection text from runtime selection API", () => {
    const runtimeGlobal = globalThis as {
      getSelection: (() => Selection | null) | undefined;
    };
    const originalGetSelection = runtimeGlobal.getSelection;
    runtimeGlobal.getSelection = () => null;

    try {
      const snapshot = capturePageSnapshotFromDocument(createFakeDocument(), {
        includeSelectionText: true,
      });
      expect(snapshot.selectionText).toBeUndefined();
    } finally {
      runtimeGlobal.getSelection = originalGetSelection;
    }
  });
});
