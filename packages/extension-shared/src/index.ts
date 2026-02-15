export {
  type ExtractionInput,
  type BrowserTag,
  supportsHostCaptureRequest,
  createBrowserPayload,
  createCaptureResponseMessage,
  createErrorMessage,
} from "./payload.js";

export {
  type HostRequestHandlingOptions,
  handleHostCaptureRequest,
} from "./transport.js";

export {
  type PageSnapshot,
  asString,
  normalizeText,
  sanitizeHeadings,
  sanitizeLinks,
  toExtractionInput,
} from "./sanitize-snapshot.js";

export { buildDocumentScript } from "./document-script.js";
