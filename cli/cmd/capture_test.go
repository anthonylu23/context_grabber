package cmd

import (
	"context"
	"os"
	"testing"

	"github.com/anthonylu23/context_grabber/cli/internal/bridge"
)

func TestToBrowserCaptureSource(t *testing.T) {
	tests := []struct {
		method  string
		want    bridge.BrowserCaptureSource
		wantErr bool
	}{
		{method: "auto", want: bridge.BrowserCaptureSourceAuto},
		{method: "applescript", want: bridge.BrowserCaptureSourceLive},
		{method: "extension", want: bridge.BrowserCaptureSourceRuntime},
		{method: "invalid", wantErr: true},
	}

	for _, tc := range tests {
		got, err := toBrowserCaptureSource(tc.method)
		if tc.wantErr {
			if err == nil {
				t.Fatalf("expected error for method=%q", tc.method)
			}
			continue
		}
		if err != nil {
			t.Fatalf("unexpected error for method=%q: %v", tc.method, err)
		}
		if got != tc.want {
			t.Fatalf("unexpected source for method=%q: want=%q got=%q", tc.method, tc.want, got)
		}
	}
}

func TestToDesktopCaptureMethod(t *testing.T) {
	tests := []struct {
		method  string
		want    bridge.DesktopCaptureMethod
		wantErr bool
	}{
		{method: "auto", want: bridge.DesktopCaptureMethodAuto},
		{method: "applescript", want: bridge.DesktopCaptureMethodAuto},
		{method: "ax", want: bridge.DesktopCaptureMethodAX},
		{method: "ocr", want: bridge.DesktopCaptureMethodOCR},
		{method: "invalid", wantErr: true},
	}

	for _, tc := range tests {
		got, err := toDesktopCaptureMethod(tc.method)
		if tc.wantErr {
			if err == nil {
				t.Fatalf("expected error for method=%q", tc.method)
			}
			continue
		}
		if err != nil {
			t.Fatalf("unexpected error for method=%q: %v", tc.method, err)
		}
		if got != tc.want {
			t.Fatalf("unexpected method for method=%q: want=%q got=%q", tc.method, tc.want, got)
		}
	}
}

func TestParseTabReference(t *testing.T) {
	windowIndex, tabIndex, err := parseTabReference("2:7")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if windowIndex != 2 || tabIndex != 7 {
		t.Fatalf("unexpected parsed value: %d:%d", windowIndex, tabIndex)
	}

	if _, _, err := parseTabReference("bad"); err == nil {
		t.Fatalf("expected error for invalid tab reference")
	}
}

func TestCaptureRequestValidateRejectsMixedSelectors(t *testing.T) {
	_, err := (captureRequest{
		focused:      true,
		appName:      "Finder",
		method:       "auto",
		timeoutMs:    1200,
		outputFormat: formatMarkdown,
	}).validate()
	if err == nil {
		t.Fatalf("expected error for mixed browser and app selectors")
	}
}

func TestCaptureBrowserWithFallbackUsesSecondTargetOnUnavailable(t *testing.T) {
	previousCaptureBrowserFunc := captureBrowserFunc
	t.Cleanup(func() {
		captureBrowserFunc = previousCaptureBrowserFunc
	})

	captureBrowserFunc = func(
		_ context.Context,
		target bridge.BrowserTarget,
		_ bridge.BrowserCaptureSource,
		_ int,
		_ bridge.BrowserCaptureMetadata,
	) (bridge.BrowserCaptureAttempt, error) {
		if target == bridge.BrowserTargetSafari {
			return bridge.BrowserCaptureAttempt{
				ExtractionMethod: "metadata_only",
				ErrorCode:        "ERR_EXTENSION_UNAVAILABLE",
				Warnings:         []string{"Safari bridge unavailable"},
				Markdown:         "fallback",
			}, nil
		}
		return bridge.BrowserCaptureAttempt{
			ExtractionMethod: "browser_extension",
			Warnings:         []string{},
			Markdown:         "# Captured from Chrome\n",
		}, nil
	}

	attempt, target, err := captureBrowserWithFallback(
		context.Background(),
		[]bridge.BrowserTarget{bridge.BrowserTargetSafari, bridge.BrowserTargetChrome},
		bridge.BrowserCaptureSourceAuto,
		1200,
		bridge.BrowserCaptureMetadata{},
	)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if target != bridge.BrowserTargetChrome {
		t.Fatalf("expected chrome fallback target, got %q", target)
	}
	if attempt.ExtractionMethod != "browser_extension" {
		t.Fatalf("expected browser_extension extraction, got %q", attempt.ExtractionMethod)
	}
}

func TestResolveBrowserTargetOverrideEnvRejectsInvalidValue(t *testing.T) {
	previousValue, hadValue := os.LookupEnv("CONTEXT_GRABBER_BROWSER_TARGET")
	t.Setenv("CONTEXT_GRABBER_BROWSER_TARGET", "invalid")
	t.Cleanup(func() {
		if hadValue {
			_ = os.Setenv("CONTEXT_GRABBER_BROWSER_TARGET", previousValue)
		} else {
			_ = os.Unsetenv("CONTEXT_GRABBER_BROWSER_TARGET")
		}
	})

	_, err := resolveBrowserTargetOverrideEnv()
	if err == nil {
		t.Fatalf("expected invalid browser target override to return error")
	}
}
