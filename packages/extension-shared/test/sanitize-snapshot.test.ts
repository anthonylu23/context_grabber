import { describe, expect, it } from "bun:test";
import {
  asString,
  normalizeText,
  sanitizeHeadings,
  sanitizeLinks,
  toExtractionInput,
} from "../src/sanitize-snapshot.js";

describe("shared sanitize-snapshot helpers", () => {
  describe("asString", () => {
    it("returns trimmed strings", () => {
      expect(asString("  hello  ")).toBe("hello");
    });

    it("returns undefined for empty strings", () => {
      expect(asString("")).toBeUndefined();
      expect(asString("   ")).toBeUndefined();
    });

    it("returns undefined for non-strings", () => {
      expect(asString(42)).toBeUndefined();
      expect(asString(null)).toBeUndefined();
      expect(asString(undefined)).toBeUndefined();
    });
  });

  describe("normalizeText", () => {
    it("normalizes whitespace and newlines", () => {
      expect(normalizeText("  hello\r\nworld  ")).toBe("hello\nworld");
      expect(normalizeText("a\n\n\n\nb")).toBe("a\n\nb");
      expect(normalizeText("trailing   \ntabs")).toBe("trailing\ntabs");
    });

    it("returns empty string for non-strings", () => {
      expect(normalizeText(42)).toBe("");
      expect(normalizeText(null)).toBe("");
    });
  });

  describe("sanitizeHeadings", () => {
    it("filters valid headings", () => {
      const result = sanitizeHeadings([
        { level: 1, text: "  Heading  " },
        { level: 8, text: "Invalid level" },
        { level: 2, text: "Details" },
        { level: 3, text: "" },
        null,
      ]);

      expect(result.length).toBe(2);
      expect(result[0]).toEqual({ level: 1, text: "Heading" });
      expect(result[1]).toEqual({ level: 2, text: "Details" });
    });

    it("returns empty array for non-arrays", () => {
      expect(sanitizeHeadings("not an array")).toEqual([]);
      expect(sanitizeHeadings(null)).toEqual([]);
    });
  });

  describe("sanitizeLinks", () => {
    it("deduplicates and filters links", () => {
      const result = sanitizeLinks([
        { text: " Docs ", href: "https://example.com/docs" },
        { text: "Docs", href: "https://example.com/docs" },
        { text: "", href: "https://example.com/blank" },
        { text: "Other", href: "https://example.com/other" },
      ]);

      expect(result.length).toBe(2);
      expect(result[0]).toEqual({ text: "Docs", href: "https://example.com/docs" });
      expect(result[1]).toEqual({ text: "Other", href: "https://example.com/other" });
    });

    it("caps at 200 links", () => {
      const links = Array.from({ length: 250 }, (_, i) => ({
        text: `Link ${i}`,
        href: `https://example.com/${i}`,
      }));

      expect(sanitizeLinks(links).length).toBe(200);
    });

    it("returns empty array for non-arrays", () => {
      expect(sanitizeLinks(null)).toEqual([]);
    });
  });

  describe("toExtractionInput", () => {
    it("produces a well-typed extraction input", () => {
      const result = toExtractionInput(
        {
          url: "https://example.com/docs",
          title: "Example Docs",
          fullText: "  Intro.\n\n\nMore.  ",
          headings: [{ level: 1, text: "  Heading  " }],
          links: [{ text: "Link", href: "https://example.com" }],
          metaDescription: "description",
          selectionText: " Selected ",
        },
        true,
        "TestBrowser",
      );

      expect(result.url).toBe("https://example.com/docs");
      expect(result.title).toBe("Example Docs");
      expect(result.fullText).toBe("Intro.\n\nMore.");
      expect(result.headings?.length).toBe(1);
      expect(result.links?.length).toBe(1);
      expect(result.metaDescription).toBe("description");
      expect(result.selectionText).toBe("Selected");
    });

    it("drops selectionText when includeSelectionText is false", () => {
      const result = toExtractionInput(
        {
          url: "https://example.com",
          title: "Example",
          fullText: "text",
          selectionText: "ignored",
        },
        false,
        "TestBrowser",
      );

      expect(result.selectionText).toBeUndefined();
    });

    it("throws for non-object snapshots", () => {
      expect(() => toExtractionInput(null, true, "Chrome")).toThrow(
        "Chrome extraction snapshot is not an object.",
      );
    });

    it("throws for missing url/title", () => {
      expect(() => toExtractionInput({ url: "https://x.com" }, true, "Safari")).toThrow(
        "Safari extraction is missing required url/title fields.",
      );
    });

    it("uses browserLabel in error messages", () => {
      expect(() => toExtractionInput("string", true, "Arc")).toThrow(
        "Arc extraction snapshot is not an object.",
      );
    });
  });
});
