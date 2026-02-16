package skills

import (
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
)

// AgentTarget identifies an AI coding agent for skill installation.
type AgentTarget string

const (
	AgentClaude   AgentTarget = "claude"
	AgentOpenCode AgentTarget = "opencode"
)

// EmbeddedAgents lists agents supported by the embedded fallback installer.
// Cursor requires Bun for .mdc conversion and is excluded from the fallback.
var EmbeddedAgents = []AgentTarget{AgentClaude, AgentOpenCode}

// InstallScope determines whether skills are installed globally or per-project.
type InstallScope string

const (
	ScopeGlobal  InstallScope = "global"
	ScopeProject InstallScope = "project"
)

// InstallResult reports what was created or removed during an install/uninstall.
type InstallResult struct {
	Agent    AgentTarget
	Scope    InstallScope
	Paths    []string
	Symlinks []string
}

// globalSkillRoot returns the canonical global skill directory.
// ~/.agents/skills/context-grabber
func globalSkillRoot() string {
	return filepath.Join(homeDir(), ".agents", "skills", "context-grabber")
}

// ResolveTargetDir returns the filesystem path where skill files should be
// placed for a given agent and scope. For global scope, this returns the
// agent-specific symlink target (not the canonical root).
func ResolveTargetDir(agent AgentTarget, scope InstallScope, cwd string) (string, error) {
	home := homeDir()

	if scope == ScopeProject {
		switch agent {
		case AgentClaude:
			return filepath.Join(cwd, ".claude", "skills", "context-grabber"), nil
		case AgentOpenCode:
			return filepath.Join(cwd, ".opencode", "skills", "context-grabber"), nil
		default:
			return "", fmt.Errorf("unsupported agent %q for embedded fallback", agent)
		}
	}

	// Global scope: agent-specific directory where the symlink will point.
	switch agent {
	case AgentClaude:
		return filepath.Join(home, ".claude", "skills", "context-grabber"), nil
	case AgentOpenCode:
		return filepath.Join(home, ".config", "opencode", "skills", "context-grabber"), nil
	default:
		return "", fmt.Errorf("unsupported agent %q for embedded fallback", agent)
	}
}

// Install copies embedded skill files to the target directory for each agent.
// For global scope, files go to ~/.agents/skills/context-grabber/ (canonical)
// and a symlink is created from the agent-specific directory.
func Install(agents []AgentTarget, scope InstallScope, cwd string) ([]InstallResult, error) {
	var results []InstallResult

	// For global scope, copy canonical files once outside the agent loop.
	if scope == ScopeGlobal {
		canonical := globalSkillRoot()
		canonicalPaths, err := copyEmbeddedFiles(canonical)
		if err != nil {
			return results, fmt.Errorf("install (global canonical): %w", err)
		}

		for _, agent := range agents {
			result := InstallResult{Agent: agent, Scope: scope, Paths: canonicalPaths}

			linkDir, err := ResolveTargetDir(agent, ScopeGlobal, "")
			if err != nil {
				return results, err
			}
			if linkDir != canonical {
				if err := ensureSymlink(canonical, linkDir); err != nil {
					return results, fmt.Errorf("symlink %s: %w", agent, err)
				}
				result.Symlinks = []string{linkDir}
			}

			results = append(results, result)
		}
	} else {
		for _, agent := range agents {
			result := InstallResult{Agent: agent, Scope: scope}

			targetDir, err := ResolveTargetDir(agent, scope, cwd)
			if err != nil {
				return results, err
			}
			paths, err := copyEmbeddedFiles(targetDir)
			if err != nil {
				return results, fmt.Errorf("install %s (project): %w", agent, err)
			}
			result.Paths = paths

			results = append(results, result)
		}
	}

	return results, nil
}

// Uninstall removes installed skill files for each agent.
func Uninstall(agents []AgentTarget, scope InstallScope, cwd string) ([]InstallResult, error) {
	var results []InstallResult

	// NOTE: Iteration order matters for multi-agent global uninstall.
	// When uninstalling multiple agents (e.g. [claude, opencode]), the first
	// agent's hasOtherGlobalSymlinks check sees the second agent's symlink
	// still present, so canonical files are preserved. After the first agent's
	// symlink is removed, the second agent sees no remaining symlinks and
	// removes the canonical files. This is correct behavior — canonical files
	// are only removed when the last symlink is gone.
	for _, agent := range agents {
		result := InstallResult{Agent: agent, Scope: scope}

		if scope == ScopeGlobal {
			// Remove symlink first.
			linkDir, err := ResolveTargetDir(agent, ScopeGlobal, "")
			if err == nil && linkDir != globalSkillRoot() {
				if removeSymlink(linkDir) {
					result.Symlinks = []string{linkDir}
				}
			}

			// Only remove canonical files if no other agent symlinks still
			// point to them. This prevents breaking other agents when
			// uninstalling a single agent from a multi-agent global install.
			if !hasOtherGlobalSymlinks(agent) {
				canonical := globalSkillRoot()
				paths := removeSkillFiles(canonical)
				result.Paths = paths
			}
		} else {
			targetDir, err := ResolveTargetDir(agent, scope, cwd)
			if err != nil {
				return results, err
			}
			paths := removeSkillFiles(targetDir)
			result.Paths = paths
		}

		results = append(results, result)
	}

	return results, nil
}

// ValidateAgent checks whether an agent string is supported by the embedded fallback.
func ValidateAgent(s string) (AgentTarget, error) {
	switch AgentTarget(strings.ToLower(s)) {
	case AgentClaude:
		return AgentClaude, nil
	case AgentOpenCode:
		return AgentOpenCode, nil
	default:
		return "", fmt.Errorf("unsupported agent %q (embedded fallback supports: claude, opencode; cursor requires bun)", s)
	}
}

// ValidateScope checks whether a scope string is valid.
func ValidateScope(s string) (InstallScope, error) {
	switch InstallScope(strings.ToLower(s)) {
	case ScopeGlobal:
		return ScopeGlobal, nil
	case ScopeProject:
		return ScopeProject, nil
	default:
		return "", fmt.Errorf("unsupported scope %q (expected global or project)", s)
	}
}

// --- internal helpers ---

// copyEmbeddedFiles writes all skill files from the embedded FS to targetDir.
func copyEmbeddedFiles(targetDir string) ([]string, error) {
	var created []string

	for _, relPath := range SkillFileList {
		dest := filepath.Join(targetDir, relPath)
		if err := os.MkdirAll(filepath.Dir(dest), 0o755); err != nil {
			return created, err
		}

		data, err := fs.ReadFile(SkillFiles, relPath)
		if err != nil {
			return created, fmt.Errorf("read embedded %s: %w", relPath, err)
		}

		if err := os.WriteFile(dest, data, 0o644); err != nil {
			return created, err
		}
		created = append(created, dest)
	}

	return created, nil
}

// ensureSymlink creates a symlink from linkPath -> targetPath.
// If the symlink already points to the correct target, it is left unchanged.
// If it exists but points elsewhere (or is not a symlink), it is replaced.
func ensureSymlink(targetPath, linkPath string) error {
	if fi, err := os.Lstat(linkPath); err == nil {
		if fi.Mode()&os.ModeSymlink != 0 {
			existing, err := os.Readlink(linkPath)
			if err == nil {
				absExisting, _ := filepath.Abs(existing)
				absTarget, _ := filepath.Abs(targetPath)
				if absExisting == absTarget {
					return nil // Already correct.
				}
			}
		}
		// Wrong target or not a symlink — remove.
		if err := os.RemoveAll(linkPath); err != nil {
			return err
		}
	}

	if err := os.MkdirAll(filepath.Dir(linkPath), 0o755); err != nil {
		return err
	}
	return os.Symlink(targetPath, linkPath)
}

// removeSymlink removes linkPath if it is a symlink pointing to globalSkillRoot().
func removeSymlink(linkPath string) bool {
	fi, err := os.Lstat(linkPath)
	if err != nil {
		return false
	}
	if fi.Mode()&os.ModeSymlink == 0 {
		return false
	}
	existing, err := os.Readlink(linkPath)
	if err != nil {
		return false
	}
	absExisting, _ := filepath.Abs(existing)
	absCanonical, _ := filepath.Abs(globalSkillRoot())
	if absExisting != absCanonical {
		return false
	}
	if err := os.Remove(linkPath); err != nil {
		return false
	}
	return true
}

// removeSkillFiles removes skill files from targetDir and cleans up empty dirs.
func removeSkillFiles(targetDir string) []string {
	var removed []string
	for _, relPath := range SkillFileList {
		p := filepath.Join(targetDir, relPath)
		if err := os.Remove(p); err == nil {
			removed = append(removed, p)
		}
	}

	// Clean up any subdirectories created for skill files (e.g. references/).
	// Derived from SkillFileList to avoid hardcoding directory names.
	subdirs := make(map[string]struct{})
	for _, relPath := range SkillFileList {
		if d := filepath.Dir(relPath); d != "." {
			subdirs[d] = struct{}{}
		}
	}
	for d := range subdirs {
		_ = os.Remove(filepath.Join(targetDir, d)) // Fails silently if not empty or missing.
	}

	// Clean up target dir if empty.
	_ = os.Remove(targetDir)

	return removed
}

// homeDirFunc is the function used to resolve the user's home directory.
// Overridable in tests to avoid writing to the real home directory.
var homeDirFunc = defaultHomeDir

// homeDir returns the user's home directory using the current homeDirFunc.
func homeDir() string {
	return homeDirFunc()
}

// defaultHomeDir returns the user's home directory, falling back to $HOME.
func defaultHomeDir() string {
	if h, err := os.UserHomeDir(); err == nil {
		return h
	}
	return os.Getenv("HOME")
}

// hasOtherGlobalSymlinks checks whether any agent other than excludeAgent
// still has a global symlink pointing to the canonical skill root.
// Used during global uninstall to decide whether canonical files can be safely
// removed.
func hasOtherGlobalSymlinks(excludeAgent AgentTarget) bool {
	canonical := globalSkillRoot()

	for _, agent := range EmbeddedAgents {
		if agent == excludeAgent {
			continue
		}

		linkDir, err := ResolveTargetDir(agent, ScopeGlobal, "")
		if err != nil {
			continue
		}

		fi, err := os.Lstat(linkDir)
		if err != nil {
			continue
		}
		if fi.Mode()&os.ModeSymlink == 0 {
			continue
		}

		existing, err := os.Readlink(linkDir)
		if err != nil {
			continue
		}
		absExisting, _ := filepath.Abs(existing)
		absCanonical, _ := filepath.Abs(canonical)
		if absExisting == absCanonical {
			return true // Another agent still points here.
		}
	}

	return false
}
