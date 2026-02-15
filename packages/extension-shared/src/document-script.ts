/**
 * Builds the JavaScript source that runs inside a browser tab to collect
 * page metadata, headings, links, body text, and (optionally) the current
 * text selection.
 *
 * This script is byte-for-byte identical for Chrome and Safari — only the
 * AppleScript wrapper that delivers it differs between browsers.
 */
export const buildDocumentScript = (includeSelectionText: boolean): string => {
  const includeSelectionLiteral = includeSelectionText ? "true" : "false";

  return `(() => {
  const normalize = (value) => {
    if (typeof value !== "string") {
      return "";
    }

    return value
      .replace(/\\r\\n?/g, "\\n")
      .replace(/[ \\t]+\\n/g, "\\n")
      .replace(/\\n{3,}/g, "\\n\\n")
      .trim();
  };

  const meta = (selector) => {
    const element = document.querySelector(selector);
    if (!element) {
      return undefined;
    }

    const content = element.getAttribute("content");
    if (typeof content !== "string") {
      return undefined;
    }

    const trimmed = content.trim();
    return trimmed.length > 0 ? trimmed : undefined;
  };

  const headings = Array.from(document.querySelectorAll("h1, h2, h3, h4, h5, h6")).map((heading) => {
    const tagName = heading.tagName.toLowerCase();
    const parsedLevel = Number.parseInt(tagName.slice(1), 10);
    return {
      level: Number.isInteger(parsedLevel) ? parsedLevel : 1,
      text: normalize(heading.textContent || ""),
    };
  }).filter((heading) => heading.text.length > 0);

  const links = Array.from(document.querySelectorAll("a[href]")).map((link) => ({
    text: normalize(link.textContent || ""),
    href: normalize(link.href || ""),
  })).filter((link) => link.text.length > 0 && link.href.length > 0).slice(0, 200);

  const selection = window.getSelection ? window.getSelection() : null;
  const selectionText = ${includeSelectionLiteral}
    ? normalize(selection ? selection.toString() : "")
    : undefined;

  return JSON.stringify({
    url: document.location ? document.location.href : "",
    title: document.title || "",
    fullText: normalize(document.body ? document.body.innerText : ""),
    headings,
    links,
    metaDescription: meta('meta[name="description"]') || meta('meta[property="og:description"]'),
    siteName: meta('meta[property="og:site_name"]') || meta('meta[name="application-name"]'),
    language: (document.documentElement && document.documentElement.lang) || undefined,
    author: meta('meta[name="author"]') || meta('meta[property="article:author"]'),
    publishedTime: meta('meta[property="article:published_time"]') || meta('meta[name="article:published_time"]'),
    selectionText,
  });
})();`;
};
