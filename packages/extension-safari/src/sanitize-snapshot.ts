/**
 * Re-exports from the shared sanitization module with Safari-specific aliases
 * for backward compatibility.
 */
import {
  type ExtractionInput,
  type PageSnapshot,
  toExtractionInput,
} from "@context-grabber/extension-shared";

export type { PageSnapshot as SafariPageSnapshot };

export const toSafariExtractionInput = (
  rawSnapshot: unknown,
  includeSelectionText: boolean,
): ExtractionInput => {
  return toExtractionInput(rawSnapshot, includeSelectionText, "Safari");
};
