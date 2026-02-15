package bridge

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

type mockDesktopRunner func(ctx context.Context, name string, args []string) (string, string, error)

func (m mockDesktopRunner) Run(ctx context.Context, name string, args []string) (string, string, error) {
	return m(ctx, name, args)
}

func TestCaptureDesktopBuildsExpectedHostCommand(t *testing.T) {
	tempRoot := t.TempDir()
	sharedTypesPath := filepath.Join(tempRoot, "packages", "shared-types", "package.json")
	if err := os.MkdirAll(filepath.Dir(sharedTypesPath), 0o755); err != nil {
		t.Fatalf("mkdir shared-types path failed: %v", err)
	}
	if err := os.WriteFile(sharedTypesPath, []byte("{}"), 0o644); err != nil {
		t.Fatalf("write shared-types marker failed: %v", err)
	}

	hostPath := filepath.Join(tempRoot, "ContextGrabberHost")
	if err := os.WriteFile(hostPath, []byte("#!/bin/sh\necho host\n"), 0o755); err != nil {
		t.Fatalf("write host binary failed: %v", err)
	}
	if err := os.Chmod(hostPath, 0o755); err != nil {
		t.Fatalf("chmod host binary failed: %v", err)
	}

	t.Setenv("CONTEXT_GRABBER_REPO_ROOT", tempRoot)
	t.Setenv("CONTEXT_GRABBER_HOST_BIN", hostPath)

	var capturedName string
	var capturedArgs []string
	restore := setSwiftCaptureRunnerForTesting(mockDesktopRunner(func(_ context.Context, name string, args []string) (string, string, error) {
		capturedName = name
		capturedArgs = append([]string{}, args...)
		return "markdown output\n", "", nil
	}))
	defer restore()

	output, err := CaptureDesktop(context.Background(), DesktopCaptureRequest{
		AppName: "Finder",
		Method:  DesktopCaptureMethodAX,
		Format:  DesktopCaptureFormatMarkdown,
	})
	if err != nil {
		t.Fatalf("CaptureDesktop returned error: %v", err)
	}
	if string(output) != "markdown output\n" {
		t.Fatalf("unexpected output: %q", string(output))
	}
	if capturedName != hostPath {
		t.Fatalf("unexpected host path: want=%q got=%q", hostPath, capturedName)
	}
	joined := strings.Join(capturedArgs, " ")
	for _, expected := range []string{"--capture", "--app", "Finder", "--method", "ax", "--format", "markdown"} {
		if !strings.Contains(joined, expected) {
			t.Fatalf("expected args to contain %q, got %q", expected, joined)
		}
	}
}

func TestCaptureDesktopRejectsMissingTarget(t *testing.T) {
	_, err := CaptureDesktop(context.Background(), DesktopCaptureRequest{
		Method: DesktopCaptureMethodAuto,
		Format: DesktopCaptureFormatMarkdown,
	})
	if err == nil {
		t.Fatalf("expected error for missing app and bundle target")
	}
}

func TestCaptureDesktopUsesInstalledHostFallbackOutsideRepo(t *testing.T) {
	t.Setenv("CONTEXT_GRABBER_REPO_ROOT", "")
	t.Setenv("CONTEXT_GRABBER_HOST_BIN", "")
	t.Chdir(t.TempDir())

	hostPath := filepath.Join(t.TempDir(), "ContextGrabberHost")
	if err := os.WriteFile(hostPath, []byte("#!/bin/sh\necho host\n"), 0o755); err != nil {
		t.Fatalf("write host binary failed: %v", err)
	}
	if err := os.Chmod(hostPath, 0o755); err != nil {
		t.Fatalf("chmod host binary failed: %v", err)
	}

	previousInstalledPath := installedHostBinaryPath
	installedHostBinaryPath = hostPath
	defer func() {
		installedHostBinaryPath = previousInstalledPath
	}()

	var capturedName string
	restore := setSwiftCaptureRunnerForTesting(mockDesktopRunner(func(_ context.Context, name string, _ []string) (string, string, error) {
		capturedName = name
		return "markdown output\n", "", nil
	}))
	defer restore()

	_, err := CaptureDesktop(context.Background(), DesktopCaptureRequest{
		AppName: "Finder",
		Method:  DesktopCaptureMethodAuto,
		Format:  DesktopCaptureFormatMarkdown,
	})
	if err != nil {
		t.Fatalf("CaptureDesktop returned error: %v", err)
	}
	if capturedName != hostPath {
		t.Fatalf("expected fallback host path %q, got %q", hostPath, capturedName)
	}
}
