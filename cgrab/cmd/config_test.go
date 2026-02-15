package cmd

import (
	"bytes"
	"path/filepath"
	"strings"
	"testing"
)

func TestConfigSetOutputDirAndShow(t *testing.T) {
	baseDir := filepath.Join(t.TempDir(), "contextgrabber")
	t.Setenv("CONTEXT_GRABBER_CLI_HOME", baseDir)

	setCommand := newConfigSetOutputDirCommand()
	setCommand.SetArgs([]string{"projects/client-a"})
	if err := setCommand.Execute(); err != nil {
		t.Fatalf("set-output-dir command failed: %v", err)
	}

	showCommand := newConfigShowCommand()
	var stdout bytes.Buffer
	showCommand.SetOut(&stdout)
	if err := showCommand.Execute(); err != nil {
		t.Fatalf("config show failed: %v", err)
	}

	output := stdout.String()
	if !strings.Contains(output, filepath.Join("projects", "client-a")) {
		t.Fatalf("expected config show output to include custom subdir, got %q", output)
	}
	if !strings.Contains(output, filepath.Join(baseDir, "projects", "client-a")) {
		t.Fatalf("expected config show output to include resolved output dir, got %q", output)
	}
}

func TestConfigSetOutputDirRejectsPathTraversal(t *testing.T) {
	setCommand := newConfigSetOutputDirCommand()
	setCommand.SetArgs([]string{"../outside"})
	if err := setCommand.Execute(); err == nil {
		t.Fatalf("expected traversal path to fail")
	}
}
