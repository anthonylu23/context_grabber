import {
  type ExtensionMessage,
  type ExtensionResponseMessage,
  type HostRequestMessage,
  isExtensionMessage,
  isHostRequestMessage,
  validateExtensionResponseMessage,
} from "@context-grabber/shared-types";

export * from "./capture.js";
export * from "./markdown.js";

export const parseNativeMessage = (value: unknown): ExtensionMessage => {
  if (!isExtensionMessage(value)) {
    throw new Error("Invalid extension message envelope.");
  }

  return value;
};

export const parseHostRequestMessage = (value: unknown): HostRequestMessage => {
  if (!isHostRequestMessage(value)) {
    throw new Error("Invalid host request message envelope.");
  }

  return value;
};

export const parseExtensionResponseMessage = (value: unknown): ExtensionResponseMessage => {
  const validation = validateExtensionResponseMessage(value);
  if (!validation.ok) {
    const issueMessages = validation.issues.map((issue) => issue.message).join("; ");
    throw new Error(`Invalid extension response message: ${issueMessages}`);
  }

  return validation.value;
};
