package cmd

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/anthonylu23/context_grabber/cgrab/internal/skills"
)

func TestResolveAgents_Defaults(t *testing.T) {
	agents, err := resolveAgents(nil)
	if err != nil {
		t.Fatal(err)
	}
	if len(agents) != len(skills.EmbeddedAgents) {
		t.Fatalf("expected %d agents, got %d", len(skills.EmbeddedAgents), len(agents))
	}
}

func TestResolveAgents_Explicit(t *testing.T) {
	agents, err := resolveAgents([]string{"claude"})
	if err != nil {
		t.Fatal(err)
	}
	if len(agents) != 1 || agents[0] != skills.AgentClaude {
		t.Fatalf("expected [claude], got %v", agents)
	}
}

func TestResolveAgents_CommaSeparated(t *testing.T) {
	agents, err := resolveAgents([]string{"claude,opencode"})
	if err != nil {
		t.Fatal(err)
	}
	if len(agents) != 2 {
		t.Fatalf("expected 2 agents, got %d", len(agents))
	}
	if agents[0] != skills.AgentClaude || agents[1] != skills.AgentOpenCode {
		t.Fatalf("expected [claude, opencode], got %v", agents)
	}
}

func TestResolveAgents_Invalid(t *testing.T) {
	_, err := resolveAgents([]string{"cursor"})
	if err == nil {
		t.Fatal("expected error for cursor in embedded fallback")
	}
	if !strings.Contains(err.Error(), "cursor requires bun") {
		t.Fatalf("expected bun requirement message, got: %v", err)
	}
}

func TestResolveAgents_Empty(t *testing.T) {
	agents, err := resolveAgents([]string{""})
	if err != nil {
		t.Fatal(err)
	}
	// Empty string should resolve to defaults.
	if len(agents) != len(skills.EmbeddedAgents) {
		t.Fatalf("expected defaults, got %v", agents)
	}
}

func TestSkillsInstallEmbeddedFallback(t *testing.T) {
	tmpDir := t.TempDir()
	cwd := filepath.Join(tmpDir, "project")
	if err := os.MkdirAll(cwd, 0o755); err != nil {
		t.Fatal(err)
	}

	// Override working directory for the test.
	origDir, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	if err := os.Chdir(cwd); err != nil {
		t.Fatal(err)
	}
	defer func() { _ = os.Chdir(origDir) }()

	// Force no-bun path by setting env to a nonexistent path.
	t.Setenv("CONTEXT_GRABBER_BUN_BIN", "/nonexistent/bun")

	cmd := newSkillsInstallCommand()
	var stdout bytes.Buffer
	var stderr bytes.Buffer
	cmd.SetOut(&stdout)
	cmd.SetErr(&stderr)
	cmd.SetArgs([]string{"--agent", "claude", "--scope", "project"})

	if err := cmd.Execute(); err != nil {
		t.Fatalf("skills install failed: %v\nstdout: %s\nstderr: %s", err, stdout.String(), stderr.String())
	}

	output := stdout.String()
	if !strings.Contains(output, "Claude Code") {
		t.Errorf("expected output to mention Claude Code, got: %s", output)
	}
	if !strings.Contains(output, "Done.") {
		t.Errorf("expected 'Done.' in output, got: %s", output)
	}

	// Verify files were installed.
	skillDir := filepath.Join(cwd, ".claude", "skills", "context-grabber")
	for _, relPath := range skills.SkillFileList {
		p := filepath.Join(skillDir, relPath)
		if _, err := os.Stat(p); os.IsNotExist(err) {
			t.Errorf("expected file %s to exist", p)
		}
	}
}

func TestSkillsUninstallEmbeddedFallback(t *testing.T) {
	tmpDir := t.TempDir()
	cwd := filepath.Join(tmpDir, "project")
	if err := os.MkdirAll(cwd, 0o755); err != nil {
		t.Fatal(err)
	}

	origDir, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	if err := os.Chdir(cwd); err != nil {
		t.Fatal(err)
	}
	defer func() { _ = os.Chdir(origDir) }()

	t.Setenv("CONTEXT_GRABBER_BUN_BIN", "/nonexistent/bun")

	// Install first.
	installCmd := newSkillsInstallCommand()
	installCmd.SetOut(&bytes.Buffer{})
	installCmd.SetErr(&bytes.Buffer{})
	installCmd.SetArgs([]string{"--agent", "claude", "--scope", "project"})
	if err := installCmd.Execute(); err != nil {
		t.Fatal(err)
	}

	// Uninstall.
	uninstallCmd := newSkillsUninstallCommand()
	var stdout bytes.Buffer
	uninstallCmd.SetOut(&stdout)
	uninstallCmd.SetErr(&bytes.Buffer{})
	uninstallCmd.SetArgs([]string{"--agent", "claude", "--scope", "project"})
	if err := uninstallCmd.Execute(); err != nil {
		t.Fatal(err)
	}

	output := stdout.String()
	if !strings.Contains(output, "Removed") {
		t.Errorf("expected 'Removed' in output, got: %s", output)
	}

	// Verify files were removed.
	skillDir := filepath.Join(cwd, ".claude", "skills", "context-grabber")
	for _, relPath := range skills.SkillFileList {
		p := filepath.Join(skillDir, relPath)
		if _, err := os.Stat(p); !os.IsNotExist(err) {
			t.Errorf("expected file %s to be removed", p)
		}
	}
}

func TestSkillsInstallInvalidScope(t *testing.T) {
	t.Setenv("CONTEXT_GRABBER_BUN_BIN", "/nonexistent/bun")

	cmd := newSkillsInstallCommand()
	cmd.SetOut(&bytes.Buffer{})
	cmd.SetErr(&bytes.Buffer{})
	cmd.SetArgs([]string{"--scope", "invalid"})

	err := cmd.Execute()
	if err == nil {
		t.Fatal("expected error for invalid scope")
	}
	if !strings.Contains(err.Error(), "unsupported scope") {
		t.Fatalf("expected 'unsupported scope' error, got: %v", err)
	}
}

func TestSkillsInstallInvalidAgent(t *testing.T) {
	t.Setenv("CONTEXT_GRABBER_BUN_BIN", "/nonexistent/bun")

	cmd := newSkillsInstallCommand()
	cmd.SetOut(&bytes.Buffer{})
	cmd.SetErr(&bytes.Buffer{})
	cmd.SetArgs([]string{"--agent", "unknown"})

	err := cmd.Execute()
	if err == nil {
		t.Fatal("expected error for invalid agent")
	}
	if !strings.Contains(err.Error(), "unsupported agent") {
		t.Fatalf("expected 'unsupported agent' error, got: %v", err)
	}
}

func TestAgentLabel(t *testing.T) {
	tests := []struct {
		agent skills.AgentTarget
		want  string
	}{
		{skills.AgentClaude, "Claude Code"},
		{skills.AgentOpenCode, "OpenCode"},
		{skills.AgentTarget("unknown"), "unknown"},
	}

	for _, tt := range tests {
		got := agentLabel(tt.agent)
		if got != tt.want {
			t.Errorf("agentLabel(%q) = %q, want %q", tt.agent, got, tt.want)
		}
	}
}
