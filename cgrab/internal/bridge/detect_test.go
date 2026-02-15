package bridge

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

type mockCommandRunner func(ctx context.Context, dir string, name string, args ...string) (string, string, error)

func (m mockCommandRunner) Run(
	ctx context.Context,
	dir string,
	name string,
	args ...string,
) (string, string, error) {
	return m(ctx, dir, name, args...)
}

func TestRunDoctorReadyWithHostBinaryAndBridgePing(t *testing.T) {
	tempRoot := t.TempDir()
	mustWriteFile(t, filepath.Join(tempRoot, "packages", "shared-types", "package.json"), "{}", 0o644)
	mustWriteFile(t, filepath.Join(tempRoot, "packages", "extension-safari", "package.json"), "{}", 0o644)
	mustWriteFile(t, filepath.Join(tempRoot, "packages", "extension-chrome", "package.json"), "{}", 0o644)

	hostPath := filepath.Join(tempRoot, "apps", "macos-host", ".build", "debug", "ContextGrabberHost")
	mustWriteFile(t, hostPath, "#!/bin/sh\necho host\n", 0o755)

	bunPath := filepath.Join(tempRoot, "bin", "bun")
	mustWriteFile(t, bunPath, "#!/bin/sh\necho bun\n", 0o755)

	t.Setenv("CONTEXT_GRABBER_REPO_ROOT", tempRoot)
	t.Setenv("CONTEXT_GRABBER_BUN_BIN", bunPath)
	t.Setenv("CONTEXT_GRABBER_HOST_BIN", hostPath)

	restore := setRunnerForTesting(mockCommandRunner(func(_ context.Context, _ string, _ string, args ...string) (string, string, error) {
		if len(args) >= 2 && args[1] == "--ping" {
			return `{"ok":true,"protocolVersion":"1"}`, "", nil
		}
		return "", "", nil
	}))
	defer restore()

	report, err := RunDoctor(context.Background())
	if err != nil {
		t.Fatalf("RunDoctor returned error: %v", err)
	}
	if report.OverallStatus != "ready" {
		t.Fatalf("expected overall_status=ready, got %s", report.OverallStatus)
	}
	if !report.HostBinaryAvailable || !report.BunAvailable {
		t.Fatalf("expected host and bun available, got report: %+v", report)
	}
}

func TestRunDoctorUnreachableWithoutHostOrBun(t *testing.T) {
	tempRoot := t.TempDir()
	mustWriteFile(t, filepath.Join(tempRoot, "packages", "shared-types", "package.json"), "{}", 0o644)
	mustWriteFile(t, filepath.Join(tempRoot, "packages", "extension-safari", "package.json"), "{}", 0o644)
	mustWriteFile(t, filepath.Join(tempRoot, "packages", "extension-chrome", "package.json"), "{}", 0o644)

	t.Setenv("CONTEXT_GRABBER_REPO_ROOT", tempRoot)
	t.Setenv("CONTEXT_GRABBER_BUN_BIN", filepath.Join(tempRoot, "missing", "bun"))
	t.Setenv("CONTEXT_GRABBER_HOST_BIN", filepath.Join(tempRoot, "missing", "ContextGrabberHost"))

	report, err := RunDoctor(context.Background())
	if err != nil {
		t.Fatalf("RunDoctor returned error: %v", err)
	}
	if report.OverallStatus != "unreachable" {
		t.Fatalf("expected overall_status=unreachable, got %s", report.OverallStatus)
	}
	if len(report.Bridges) != 2 {
		t.Fatalf("expected 2 bridge statuses, got %d", len(report.Bridges))
	}
	if !strings.Contains(strings.Join(report.Warnings, " | "), "bun not found") {
		t.Fatalf("expected bun warning in %v", report.Warnings)
	}
}

func TestRunDoctorReadyWithInstalledHostFallbackOutsideRepo(t *testing.T) {
	t.Setenv("CONTEXT_GRABBER_REPO_ROOT", "")
	t.Setenv("CONTEXT_GRABBER_BUN_BIN", "")
	t.Setenv("CONTEXT_GRABBER_HOST_BIN", "")
	t.Chdir(t.TempDir())

	hostPath := filepath.Join(t.TempDir(), "ContextGrabberHost")
	mustWriteFile(t, hostPath, "#!/bin/sh\necho host\n", 0o755)

	previousInstalledPath := installedHostBinaryPath
	installedHostBinaryPath = hostPath
	defer func() {
		installedHostBinaryPath = previousInstalledPath
	}()

	report, err := RunDoctor(context.Background())
	if err != nil {
		t.Fatalf("RunDoctor returned error: %v", err)
	}
	if report.OverallStatus != "ready" {
		t.Fatalf("expected overall_status=ready, got %s", report.OverallStatus)
	}
	if !report.HostBinaryAvailable {
		t.Fatalf("expected host binary available, got report: %+v", report)
	}
	if report.HostBinaryPath != hostPath {
		t.Fatalf("expected host binary path %q, got %q", hostPath, report.HostBinaryPath)
	}
}

func mustWriteFile(t *testing.T, path string, contents string, mode os.FileMode) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatalf("mkdir failed for %s: %v", path, err)
	}
	if err := os.WriteFile(path, []byte(contents), mode); err != nil {
		t.Fatalf("write file failed for %s: %v", path, err)
	}
	if err := os.Chmod(path, mode); err != nil {
		t.Fatalf("chmod failed for %s: %v", path, err)
	}
}
