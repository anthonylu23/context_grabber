package cmd

import (
	"bytes"
	"context"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/anthonylu23/context_grabber/cgrab/internal/bridge"
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
	tests := []struct {
		input   string
		wantWin int
		wantTab int
		wantErr bool
	}{
		{input: "2:7", wantWin: 2, wantTab: 7},
		{input: "w2:t7", wantWin: 2, wantTab: 7},
		{input: "w1:t1", wantWin: 1, wantTab: 1},
		{input: "w0:t1", wantErr: true},
		{input: "chrome", wantErr: true},
		{input: "bad", wantErr: true},
	}

	for _, tc := range tests {
		windowIndex, tabIndex, err := parseTabReference(tc.input)
		if tc.wantErr {
			if err == nil {
				t.Fatalf("expected error for input=%q", tc.input)
			}
			continue
		}
		if err != nil {
			t.Fatalf("unexpected error for input=%q: %v", tc.input, err)
		}
		if windowIndex != tc.wantWin || tabIndex != tc.wantTab {
			t.Fatalf("input=%q: want %d:%d, got %d:%d", tc.input, tc.wantWin, tc.wantTab, windowIndex, tabIndex)
		}
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
	previousEnsureHostAppRunningFunc := ensureHostAppRunningFunc
	t.Cleanup(func() {
		captureBrowserFunc = previousCaptureBrowserFunc
		ensureHostAppRunningFunc = previousEnsureHostAppRunningFunc
	})
	ensureHostAppRunningFunc = func(context.Context) (bool, error) {
		return false, nil
	}

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

func TestRunBrowserCaptureContinuesWhenHostAppAutolaunchFails(t *testing.T) {
	previousCaptureBrowserFunc := captureBrowserFunc
	previousEnsureHostAppRunningFunc := ensureHostAppRunningFunc
	t.Cleanup(func() {
		captureBrowserFunc = previousCaptureBrowserFunc
		ensureHostAppRunningFunc = previousEnsureHostAppRunningFunc
	})

	ensureHostAppRunningFunc = func(context.Context) (bool, error) {
		return false, os.ErrNotExist
	}
	captureBrowserFunc = func(
		_ context.Context,
		_ bridge.BrowserTarget,
		_ bridge.BrowserCaptureSource,
		_ int,
		_ bridge.BrowserCaptureMetadata,
	) (bridge.BrowserCaptureAttempt, error) {
		return bridge.BrowserCaptureAttempt{
			ExtractionMethod: "browser_extension",
			Warnings:         []string{},
			Markdown:         "# Browser Capture\n",
		}, nil
	}

	rendered, err := runBrowserCapture(context.Background(), captureRequest{
		focused:      true,
		method:       "auto",
		timeoutMs:    1200,
		outputFormat: formatMarkdown,
	}, io.Discard)
	if err != nil {
		t.Fatalf("runBrowserCapture returned error: %v", err)
	}
	if string(rendered) != "# Browser Capture\n" {
		t.Fatalf("unexpected rendered output: %q", string(rendered))
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

func TestCaptureCommandWritesToDefaultConfiguredPathWhenFileFlagOmitted(t *testing.T) {
	previousCaptureBrowserFunc := captureBrowserFunc
	previousNowFunc := nowFunc
	t.Cleanup(func() {
		captureBrowserFunc = previousCaptureBrowserFunc
		nowFunc = previousNowFunc
	})

	baseDir := filepath.Join(t.TempDir(), "contextgrabber")
	t.Setenv("CONTEXT_GRABBER_CLI_HOME", baseDir)
	nowFunc = func() time.Time {
		return time.Date(2026, time.February, 15, 13, 30, 45, 123_000_000, time.UTC)
	}
	captureBrowserFunc = func(
		_ context.Context,
		_ bridge.BrowserTarget,
		_ bridge.BrowserCaptureSource,
		_ int,
		_ bridge.BrowserCaptureMetadata,
	) (bridge.BrowserCaptureAttempt, error) {
		return bridge.BrowserCaptureAttempt{
			ExtractionMethod: "browser_extension",
			Warnings:         []string{},
			Markdown:         "# Captured Content\n",
		}, nil
	}

	options := defaultGlobalOptions()
	command := newCaptureCommand(options)
	command.SetArgs([]string{"--focused"})
	var stdout bytes.Buffer
	command.SetOut(&stdout)
	command.SetErr(&stdout)

	if err := command.Execute(); err != nil {
		t.Fatalf("capture command returned error: %v", err)
	}

	expectedFile := filepath.Join(baseDir, "captures", "capture-20260215-133045.123.md")
	raw, err := os.ReadFile(expectedFile)
	if err != nil {
		t.Fatalf("expected capture file %q to exist: %v", expectedFile, err)
	}
	if string(raw) != "# Captured Content\n" {
		t.Fatalf("unexpected capture file contents: %q", string(raw))
	}
	if !strings.Contains(stdout.String(), expectedFile) {
		t.Fatalf("expected command output to include saved path, got %q", stdout.String())
	}
}
