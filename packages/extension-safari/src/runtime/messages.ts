export const CAPTURE_ACTIVE_TAB_MESSAGE_TYPE = "context-grabber.capture-active-tab";
export const DEFAULT_NATIVE_HOST_PORT_NAME = "context-grabber.native-host";

export interface CaptureActiveTabMessage {
  type: typeof CAPTURE_ACTIVE_TAB_MESSAGE_TYPE;
  includeSelectionText: boolean;
}

export const createCaptureActiveTabMessage = (
  includeSelectionText: boolean,
): CaptureActiveTabMessage => {
  return {
    type: CAPTURE_ACTIVE_TAB_MESSAGE_TYPE,
    includeSelectionText,
  };
};

export const isCaptureActiveTabMessage = (value: unknown): value is CaptureActiveTabMessage => {
  if (typeof value !== "object" || value === null) {
    return false;
  }

  const record = value as Record<string, unknown>;
  return (
    record.type === CAPTURE_ACTIVE_TAB_MESSAGE_TYPE &&
    typeof record.includeSelectionText === "boolean"
  );
};
