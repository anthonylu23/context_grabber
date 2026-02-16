package skills

import (
	"io/fs"
	"os"
	"path/filepath"
	"testing"
)

func TestResolveTargetDir_Claude(t *testing.T) {
	cwd := "/projects/myapp"

	dir, err := ResolveTargetDir(AgentClaude, ScopeProject, cwd)
	if err != nil {
		t.Fatal(err)
	}
	want := filepath.Join(cwd, ".claude", "skills", "context-grabber")
	if dir != want {
		t.Errorf("claude project: got %q, want %q", dir, want)
	}

	dir, err = ResolveTargetDir(AgentClaude, ScopeGlobal, cwd)
	if err != nil {
		t.Fatal(err)
	}
	home := homeDir()
	want = filepath.Join(home, ".claude", "skills", "context-grabber")
	if dir != want {
		t.Errorf("claude global: got %q, want %q", dir, want)
	}
}

func TestResolveTargetDir_OpenCode(t *testing.T) {
	cwd := "/projects/myapp"

	dir, err := ResolveTargetDir(AgentOpenCode, ScopeProject, cwd)
	if err != nil {
		t.Fatal(err)
	}
	want := filepath.Join(cwd, ".opencode", "skills", "context-grabber")
	if dir != want {
		t.Errorf("opencode project: got %q, want %q", dir, want)
	}

	dir, err = ResolveTargetDir(AgentOpenCode, ScopeGlobal, cwd)
	if err != nil {
		t.Fatal(err)
	}
	home := homeDir()
	want = filepath.Join(home, ".config", "opencode", "skills", "context-grabber")
	if dir != want {
		t.Errorf("opencode global: got %q, want %q", dir, want)
	}
}

func TestResolveTargetDir_UnsupportedAgent(t *testing.T) {
	_, err := ResolveTargetDir("cursor", ScopeProject, "/tmp")
	if err == nil {
		t.Fatal("expected error for unsupported agent")
	}
}

func TestValidateAgent(t *testing.T) {
	tests := []struct {
		input string
		want  AgentTarget
		ok    bool
	}{
		{"claude", AgentClaude, true},
		{"Claude", AgentClaude, true},
		{"opencode", AgentOpenCode, true},
		{"OpenCode", AgentOpenCode, true},
		{"cursor", "", false},
		{"unknown", "", false},
	}

	for _, tt := range tests {
		got, err := ValidateAgent(tt.input)
		if tt.ok && err != nil {
			t.Errorf("ValidateAgent(%q): unexpected error: %v", tt.input, err)
		}
		if !tt.ok && err == nil {
			t.Errorf("ValidateAgent(%q): expected error", tt.input)
		}
		if got != tt.want {
			t.Errorf("ValidateAgent(%q) = %q, want %q", tt.input, got, tt.want)
		}
	}
}

func TestValidateScope(t *testing.T) {
	tests := []struct {
		input string
		want  InstallScope
		ok    bool
	}{
		{"global", ScopeGlobal, true},
		{"Global", ScopeGlobal, true},
		{"project", ScopeProject, true},
		{"Project", ScopeProject, true},
		{"invalid", "", false},
	}

	for _, tt := range tests {
		got, err := ValidateScope(tt.input)
		if tt.ok && err != nil {
			t.Errorf("ValidateScope(%q): unexpected error: %v", tt.input, err)
		}
		if !tt.ok && err == nil {
			t.Errorf("ValidateScope(%q): expected error", tt.input)
		}
		if got != tt.want {
			t.Errorf("ValidateScope(%q) = %q, want %q", tt.input, got, tt.want)
		}
	}
}

func TestEmbeddedFilesReadable(t *testing.T) {
	for _, relPath := range SkillFileList {
		data, err := fs.ReadFile(SkillFiles, relPath)
		if err != nil {
			t.Errorf("read embedded %s: %v", relPath, err)
			continue
		}
		if len(data) == 0 {
			t.Errorf("embedded %s is empty", relPath)
		}
	}
}

func TestInstallProject_Claude(t *testing.T) {
	tmpDir := t.TempDir()
	cwd := filepath.Join(tmpDir, "project")
	if err := os.MkdirAll(cwd, 0o755); err != nil {
		t.Fatal(err)
	}

	results, err := Install([]AgentTarget{AgentClaude}, ScopeProject, cwd)
	if err != nil {
		t.Fatal(err)
	}

	if len(results) != 1 {
		t.Fatalf("expected 1 result, got %d", len(results))
	}

	r := results[0]
	if r.Agent != AgentClaude {
		t.Errorf("agent: got %q, want %q", r.Agent, AgentClaude)
	}
	if r.Scope != ScopeProject {
		t.Errorf("scope: got %q, want %q", r.Scope, ScopeProject)
	}
	if len(r.Paths) != len(SkillFileList) {
		t.Errorf("paths: got %d, want %d", len(r.Paths), len(SkillFileList))
	}
	if len(r.Symlinks) != 0 {
		t.Errorf("symlinks: got %d, want 0", len(r.Symlinks))
	}

	// Verify files exist.
	targetDir := filepath.Join(cwd, ".claude", "skills", "context-grabber")
	for _, relPath := range SkillFileList {
		p := filepath.Join(targetDir, relPath)
		if _, err := os.Stat(p); os.IsNotExist(err) {
			t.Errorf("expected file %s to exist", p)
		}
	}
}

func TestInstallProject_OpenCode(t *testing.T) {
	tmpDir := t.TempDir()
	cwd := filepath.Join(tmpDir, "project")
	if err := os.MkdirAll(cwd, 0o755); err != nil {
		t.Fatal(err)
	}

	results, err := Install([]AgentTarget{AgentOpenCode}, ScopeProject, cwd)
	if err != nil {
		t.Fatal(err)
	}

	if len(results) != 1 {
		t.Fatalf("expected 1 result, got %d", len(results))
	}

	targetDir := filepath.Join(cwd, ".opencode", "skills", "context-grabber")
	for _, relPath := range SkillFileList {
		p := filepath.Join(targetDir, relPath)
		if _, err := os.Stat(p); os.IsNotExist(err) {
			t.Errorf("expected file %s to exist", p)
		}
	}
}

func TestInstallAndUninstallRoundTrip(t *testing.T) {
	tmpDir := t.TempDir()
	cwd := filepath.Join(tmpDir, "project")
	if err := os.MkdirAll(cwd, 0o755); err != nil {
		t.Fatal(err)
	}

	agents := []AgentTarget{AgentClaude, AgentOpenCode}

	// Install.
	_, err := Install(agents, ScopeProject, cwd)
	if err != nil {
		t.Fatal(err)
	}

	// Verify files exist.
	claudeDir := filepath.Join(cwd, ".claude", "skills", "context-grabber")
	opencodeDir := filepath.Join(cwd, ".opencode", "skills", "context-grabber")
	for _, dir := range []string{claudeDir, opencodeDir} {
		for _, relPath := range SkillFileList {
			p := filepath.Join(dir, relPath)
			if _, err := os.Stat(p); os.IsNotExist(err) {
				t.Errorf("expected file %s to exist after install", p)
			}
		}
	}

	// Uninstall.
	unResults, err := Uninstall(agents, ScopeProject, cwd)
	if err != nil {
		t.Fatal(err)
	}

	if len(unResults) != 2 {
		t.Fatalf("expected 2 uninstall results, got %d", len(unResults))
	}

	// Verify files removed.
	for _, dir := range []string{claudeDir, opencodeDir} {
		for _, relPath := range SkillFileList {
			p := filepath.Join(dir, relPath)
			if _, err := os.Stat(p); !os.IsNotExist(err) {
				t.Errorf("expected file %s to be removed after uninstall", p)
			}
		}
	}
}

func TestInstallOverwritesExisting(t *testing.T) {
	tmpDir := t.TempDir()
	cwd := filepath.Join(tmpDir, "project")

	// Create a pre-existing file.
	targetDir := filepath.Join(cwd, ".claude", "skills", "context-grabber")
	if err := os.MkdirAll(targetDir, 0o755); err != nil {
		t.Fatal(err)
	}
	existingFile := filepath.Join(targetDir, "SKILL.md")
	if err := os.WriteFile(existingFile, []byte("old content"), 0o644); err != nil {
		t.Fatal(err)
	}

	// Install should overwrite.
	_, err := Install([]AgentTarget{AgentClaude}, ScopeProject, cwd)
	if err != nil {
		t.Fatal(err)
	}

	data, err := os.ReadFile(existingFile)
	if err != nil {
		t.Fatal(err)
	}
	if string(data) == "old content" {
		t.Error("expected SKILL.md to be overwritten, but it still has old content")
	}
}

func TestCopyEmbeddedFilesContent(t *testing.T) {
	tmpDir := t.TempDir()

	paths, err := copyEmbeddedFiles(tmpDir)
	if err != nil {
		t.Fatal(err)
	}

	if len(paths) != len(SkillFileList) {
		t.Fatalf("expected %d files, got %d", len(SkillFileList), len(paths))
	}

	// Verify content matches embedded source.
	for _, relPath := range SkillFileList {
		embedded, err := fs.ReadFile(SkillFiles, relPath)
		if err != nil {
			t.Fatal(err)
		}

		written, err := os.ReadFile(filepath.Join(tmpDir, relPath))
		if err != nil {
			t.Fatal(err)
		}

		if string(embedded) != string(written) {
			t.Errorf("content mismatch for %s", relPath)
		}
	}
}

func TestEnsureSymlink(t *testing.T) {
	tmpDir := t.TempDir()

	target := filepath.Join(tmpDir, "target")
	if err := os.MkdirAll(target, 0o755); err != nil {
		t.Fatal(err)
	}

	link := filepath.Join(tmpDir, "link")

	// Create symlink.
	if err := ensureSymlink(target, link); err != nil {
		t.Fatal(err)
	}
	fi, err := os.Lstat(link)
	if err != nil {
		t.Fatal(err)
	}
	if fi.Mode()&os.ModeSymlink == 0 {
		t.Error("expected symlink")
	}

	// Calling again should be idempotent.
	if err := ensureSymlink(target, link); err != nil {
		t.Fatal(err)
	}

	// Replace with wrong target.
	wrongTarget := filepath.Join(tmpDir, "wrong")
	if err := os.MkdirAll(wrongTarget, 0o755); err != nil {
		t.Fatal(err)
	}
	os.Remove(link)
	if err := os.Symlink(wrongTarget, link); err != nil {
		t.Fatal(err)
	}

	// ensureSymlink should replace it.
	if err := ensureSymlink(target, link); err != nil {
		t.Fatal(err)
	}
	resolved, err := os.Readlink(link)
	if err != nil {
		t.Fatal(err)
	}
	absResolved, _ := filepath.Abs(resolved)
	absTarget, _ := filepath.Abs(target)
	if absResolved != absTarget {
		t.Errorf("symlink: got %q, want %q", absResolved, absTarget)
	}
}

// setTestHome overrides homeDir to use a temp directory and returns a cleanup function.
func setTestHome(t *testing.T) string {
	t.Helper()
	tmpHome := t.TempDir()
	original := homeDirFunc
	homeDirFunc = func() string { return tmpHome }
	t.Cleanup(func() { homeDirFunc = original })
	return tmpHome
}

func TestInstallGlobal_SingleAgent(t *testing.T) {
	tmpHome := setTestHome(t)

	results, err := Install([]AgentTarget{AgentClaude}, ScopeGlobal, "")
	if err != nil {
		t.Fatal(err)
	}

	if len(results) != 1 {
		t.Fatalf("expected 1 result, got %d", len(results))
	}

	r := results[0]
	if r.Agent != AgentClaude {
		t.Errorf("agent: got %q, want %q", r.Agent, AgentClaude)
	}
	if r.Scope != ScopeGlobal {
		t.Errorf("scope: got %q, want %q", r.Scope, ScopeGlobal)
	}
	if len(r.Paths) != len(SkillFileList) {
		t.Errorf("paths: got %d, want %d", len(r.Paths), len(SkillFileList))
	}
	if len(r.Symlinks) != 1 {
		t.Fatalf("expected 1 symlink, got %d", len(r.Symlinks))
	}

	// Verify canonical files exist.
	canonical := filepath.Join(tmpHome, ".agents", "skills", "context-grabber")
	for _, relPath := range SkillFileList {
		p := filepath.Join(canonical, relPath)
		if _, err := os.Stat(p); os.IsNotExist(err) {
			t.Errorf("expected canonical file %s to exist", p)
		}
	}

	// Verify symlink points to canonical.
	claudeDir := filepath.Join(tmpHome, ".claude", "skills", "context-grabber")
	fi, err := os.Lstat(claudeDir)
	if err != nil {
		t.Fatalf("expected symlink at %s: %v", claudeDir, err)
	}
	if fi.Mode()&os.ModeSymlink == 0 {
		t.Errorf("expected %s to be a symlink", claudeDir)
	}
	linkTarget, err := os.Readlink(claudeDir)
	if err != nil {
		t.Fatal(err)
	}
	absLink, _ := filepath.Abs(linkTarget)
	absCanonical, _ := filepath.Abs(canonical)
	if absLink != absCanonical {
		t.Errorf("symlink target: got %q, want %q", absLink, absCanonical)
	}
}

func TestInstallGlobal_MultiAgent(t *testing.T) {
	tmpHome := setTestHome(t)

	results, err := Install([]AgentTarget{AgentClaude, AgentOpenCode}, ScopeGlobal, "")
	if err != nil {
		t.Fatal(err)
	}

	if len(results) != 2 {
		t.Fatalf("expected 2 results, got %d", len(results))
	}

	// Verify both agents have symlinks.
	claudeDir := filepath.Join(tmpHome, ".claude", "skills", "context-grabber")
	opencodeDir := filepath.Join(tmpHome, ".config", "opencode", "skills", "context-grabber")
	for _, dir := range []string{claudeDir, opencodeDir} {
		fi, err := os.Lstat(dir)
		if err != nil {
			t.Fatalf("expected symlink at %s: %v", dir, err)
		}
		if fi.Mode()&os.ModeSymlink == 0 {
			t.Errorf("expected %s to be a symlink", dir)
		}
	}

	// Verify canonical files exist and are accessible through symlinks.
	canonical := filepath.Join(tmpHome, ".agents", "skills", "context-grabber")
	for _, relPath := range SkillFileList {
		// Via canonical path.
		p := filepath.Join(canonical, relPath)
		if _, err := os.Stat(p); os.IsNotExist(err) {
			t.Errorf("expected canonical file %s to exist", p)
		}
		// Via symlink (Claude).
		p = filepath.Join(claudeDir, relPath)
		if _, err := os.Stat(p); os.IsNotExist(err) {
			t.Errorf("expected file via symlink %s to exist", p)
		}
	}
}

func TestUninstallGlobal_SingleAgent_PreservesCanonical(t *testing.T) {
	tmpHome := setTestHome(t)

	// Install for both agents.
	_, err := Install([]AgentTarget{AgentClaude, AgentOpenCode}, ScopeGlobal, "")
	if err != nil {
		t.Fatal(err)
	}

	// Uninstall only Claude.
	results, err := Uninstall([]AgentTarget{AgentClaude}, ScopeGlobal, "")
	if err != nil {
		t.Fatal(err)
	}

	if len(results) != 1 {
		t.Fatalf("expected 1 result, got %d", len(results))
	}

	// Verify Claude symlink was removed.
	claudeDir := filepath.Join(tmpHome, ".claude", "skills", "context-grabber")
	if _, err := os.Lstat(claudeDir); !os.IsNotExist(err) {
		t.Errorf("expected Claude symlink to be removed")
	}

	// Verify canonical files still exist (OpenCode still needs them).
	canonical := filepath.Join(tmpHome, ".agents", "skills", "context-grabber")
	for _, relPath := range SkillFileList {
		p := filepath.Join(canonical, relPath)
		if _, err := os.Stat(p); os.IsNotExist(err) {
			t.Errorf("expected canonical file %s to still exist (OpenCode symlink active)", p)
		}
	}

	// Verify OpenCode symlink still works.
	opencodeDir := filepath.Join(tmpHome, ".config", "opencode", "skills", "context-grabber")
	fi, err := os.Lstat(opencodeDir)
	if err != nil {
		t.Fatalf("expected OpenCode symlink to still exist: %v", err)
	}
	if fi.Mode()&os.ModeSymlink == 0 {
		t.Errorf("expected %s to still be a symlink", opencodeDir)
	}
}

func TestUninstallGlobal_LastAgent_RemovesCanonical(t *testing.T) {
	setTestHome(t)

	// Install for Claude only.
	_, err := Install([]AgentTarget{AgentClaude}, ScopeGlobal, "")
	if err != nil {
		t.Fatal(err)
	}

	// Uninstall Claude — should also remove canonical files since no other symlinks.
	results, err := Uninstall([]AgentTarget{AgentClaude}, ScopeGlobal, "")
	if err != nil {
		t.Fatal(err)
	}

	if len(results) != 1 {
		t.Fatalf("expected 1 result, got %d", len(results))
	}

	// Paths should be non-empty (canonical files were removed).
	if len(results[0].Paths) == 0 {
		t.Error("expected canonical files to be removed when last agent is uninstalled")
	}
}

func TestUninstallGlobal_AllAgents_RemovesCanonical(t *testing.T) {
	tmpHome := setTestHome(t)

	// Install for both.
	_, err := Install([]AgentTarget{AgentClaude, AgentOpenCode}, ScopeGlobal, "")
	if err != nil {
		t.Fatal(err)
	}

	// Uninstall both.
	_, err = Uninstall([]AgentTarget{AgentClaude, AgentOpenCode}, ScopeGlobal, "")
	if err != nil {
		t.Fatal(err)
	}

	// Verify all files and symlinks are removed.
	canonical := filepath.Join(tmpHome, ".agents", "skills", "context-grabber")
	if _, err := os.Stat(canonical); !os.IsNotExist(err) {
		t.Errorf("expected canonical dir to be removed")
	}

	claudeDir := filepath.Join(tmpHome, ".claude", "skills", "context-grabber")
	if _, err := os.Lstat(claudeDir); !os.IsNotExist(err) {
		t.Errorf("expected Claude symlink to be removed")
	}

	opencodeDir := filepath.Join(tmpHome, ".config", "opencode", "skills", "context-grabber")
	if _, err := os.Lstat(opencodeDir); !os.IsNotExist(err) {
		t.Errorf("expected OpenCode symlink to be removed")
	}
}
