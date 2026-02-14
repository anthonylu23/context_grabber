import { type CaptureNativeMessage, isCaptureNativeMessage } from "@context-grabber/shared-types";

export const parseNativeMessage = (value: unknown): CaptureNativeMessage => {
  if (!isCaptureNativeMessage(value)) {
    throw new Error("Invalid native message envelope.");
  }

  return value;
};
