import { describe, expect, it } from "bun:test";
import { buildSafariDocumentScript, toSafariExtractionInput } from "../src/extract-active-tab.js";

describe("safari active-tab extraction helpers", () => {
  it("sanitizes raw snapshots into Safari extraction payloads", () => {
    const payload = toSafariExtractionInput(
      {
        url: "https://example.com/docs",
        title: "Example Docs",
        fullText: "  Intro section.\n\n\nMore details.  ",
        headings: [
          { level: 1, text: "  Heading  " },
          { level: 8, text: "Ignored" },
          { level: 2, text: "Details" },
        ],
        links: [
          { text: " Docs ", href: "https://example.com/docs" },
          { text: "Docs", href: "https://example.com/docs" },
          { text: "", href: "https://example.com/blank" },
        ],
        selectionText: " Selected line ",
        metaDescription: "description",
      },
      true,
    );

    expect(payload.url).toBe("https://example.com/docs");
    expect(payload.title).toBe("Example Docs");
    expect(payload.fullText).toBe("Intro section.\n\nMore details.");
    expect((payload.headings ?? []).length).toBe(2);
    expect((payload.links ?? []).length).toBe(1);
    expect(payload.selectionText).toBe("Selected line");
    expect(payload.metaDescription).toBe("description");
  });

  it("drops selection text when request does not include it", () => {
    const payload = toSafariExtractionInput(
      {
        url: "https://example.com",
        title: "Example",
        fullText: "Text",
        headings: [],
        links: [],
        selectionText: "Will be omitted",
      },
      false,
    );

    expect(payload.selectionText).toBe(undefined);
  });

  it("embeds includeSelectionText behavior in generated script", () => {
    const withSelection = buildSafariDocumentScript(true);
    const withoutSelection = buildSafariDocumentScript(false);

    expect(withSelection.includes("const selectionText = true")).toBe(true);
    expect(withoutSelection.includes("const selectionText = false")).toBe(true);
  });
});
