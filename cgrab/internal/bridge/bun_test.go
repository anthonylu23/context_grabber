package bridge

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

type mockBunRunner func(
	ctx context.Context,
	dir string,
	name string,
	args []string,
	env []string,
) (string, string, error)

func (m mockBunRunner) Run(
	ctx context.Context,
	dir string,
	name string,
	args []string,
	env []string,
) (string, string, error) {
	return m(ctx, dir, name, args, env)
}

func TestCaptureBrowserPassesTargetAndSourceToBridgeScript(t *testing.T) {
	tempRoot := t.TempDir()
	mustWriteExecutableFile(t, filepath.Join(tempRoot, "packages", "shared-types", "package.json"), "{}")
	mustWriteExecutableFile(t, filepath.Join(tempRoot, "cgrab", "internal", "bridge", "browser_capture.ts"), "// script")
	bunPath := filepath.Join(tempRoot, "bin", "bun")
	mustWriteExecutableFile(t, bunPath, "#!/bin/sh\necho bun\n")

	t.Setenv("CONTEXT_GRABBER_REPO_ROOT", tempRoot)
	t.Setenv("CONTEXT_GRABBER_BUN_BIN", bunPath)

	var capturedName string
	var capturedArgs []string
	restore := setBunCaptureRunnerForTesting(mockBunRunner(func(
		_ context.Context,
		_ string,
		name string,
		args []string,
		_ []string,
	) (string, string, error) {
		capturedName = name
		capturedArgs = append([]string{}, args...)
		return `{"extractionMethod":"browser_extension","warnings":[],"markdown":"# ok\n","payload":{"browser":"safari"}}`, "", nil
	}))
	defer restore()

	attempt, err := CaptureBrowser(
		context.Background(),
		BrowserTargetSafari,
		BrowserCaptureSourceLive,
		1200,
		BrowserCaptureMetadata{Title: "Title"},
	)
	if err != nil {
		t.Fatalf("CaptureBrowser returned error: %v", err)
	}
	if capturedName != bunPath {
		t.Fatalf("expected bun binary %q, got %q", bunPath, capturedName)
	}
	joined := strings.Join(capturedArgs, " ")
	for _, expected := range []string{"--target safari", "--source live", "--timeout-ms 1200"} {
		if !strings.Contains(joined, expected) {
			t.Fatalf("expected args to contain %q, got %q", expected, joined)
		}
	}
	if attempt.ExtractionMethod != "browser_extension" {
		t.Fatalf("unexpected extraction method: %q", attempt.ExtractionMethod)
	}
}

func mustWriteExecutableFile(t *testing.T, path string, content string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatalf("mkdir failed for %s: %v", path, err)
	}
	mode := os.FileMode(0o644)
	if strings.HasSuffix(path, "bun") {
		mode = 0o755
	}
	if err := os.WriteFile(path, []byte(content), mode); err != nil {
		t.Fatalf("write file failed for %s: %v", path, err)
	}
	if mode&0o111 != 0 {
		if err := os.Chmod(path, mode); err != nil {
			t.Fatalf("chmod failed for %s: %v", path, err)
		}
	}
}
