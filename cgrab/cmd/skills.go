package cmd

import (
	"fmt"
	"os"
	"os/exec"
	"strings"

	"github.com/anthonylu23/context_grabber/cgrab/internal/skills"
	"github.com/spf13/cobra"
)

func newSkillsCommand() *cobra.Command {
	skillsCmd := &cobra.Command{
		Use:   "skills",
		Short: "Manage agent skill definitions",
		Long:  "Install or uninstall Context Grabber skill definitions for AI coding agents (Claude Code, OpenCode, Cursor).",
	}

	skillsCmd.AddCommand(newSkillsInstallCommand())
	skillsCmd.AddCommand(newSkillsUninstallCommand())
	return skillsCmd
}

func newSkillsInstallCommand() *cobra.Command {
	var agentFlag []string
	var scopeFlag string

	cmd := &cobra.Command{
		Use:   "install",
		Short: "Install agent skill definitions",
		Long: `Install Context Grabber skill definitions for AI coding agents.

When Bun is available, launches the interactive installer with support for
Claude Code, OpenCode, and Cursor. When Bun is unavailable, falls back to
the embedded installer (Claude Code and OpenCode only; Cursor requires Bun
for .mdc format conversion).`,
		Example: "  cgrab skills install\n  cgrab skills install --agent claude --scope project\n  cgrab skills install --agent claude --agent opencode --scope global",
		RunE: func(cmd *cobra.Command, _ []string) error {
			return runSkillsAction(cmd, agentFlag, scopeFlag, false)
		},
	}

	cmd.Flags().StringSliceVar(&agentFlag, "agent", nil, "agent targets: claude, opencode, cursor")
	cmd.Flags().StringVar(&scopeFlag, "scope", "global", "install scope: global or project")
	return cmd
}

func newSkillsUninstallCommand() *cobra.Command {
	var agentFlag []string
	var scopeFlag string

	cmd := &cobra.Command{
		Use:     "uninstall",
		Short:   "Uninstall agent skill definitions",
		Long:    "Remove previously installed Context Grabber skill definitions.",
		Example: "  cgrab skills uninstall\n  cgrab skills uninstall --agent claude --scope project",
		RunE: func(cmd *cobra.Command, _ []string) error {
			return runSkillsAction(cmd, agentFlag, scopeFlag, true)
		},
	}

	cmd.Flags().StringSliceVar(&agentFlag, "agent", nil, "agent targets: claude, opencode, cursor")
	cmd.Flags().StringVar(&scopeFlag, "scope", "global", "install scope: global or project")
	return cmd
}

// runSkillsAction attempts Bun delegation first, falling back to embedded install.
func runSkillsAction(cmd *cobra.Command, agentFlag []string, scopeFlag string, uninstall bool) error {
	bunPath := resolveBunPathForSkills()
	agentFlagChanged := cmd.Flags().Changed("agent")
	scopeFlagChanged := cmd.Flags().Changed("scope")
	hasExplicitSelection := agentFlagChanged || scopeFlagChanged

	// Bun available: delegate to the interactive TS installer.
	if bunPath != "" {
		err := runBunInstaller(cmd, bunPath, agentFlag, scopeFlag, agentFlagChanged, scopeFlagChanged, uninstall)
		if err == nil {
			return nil
		}
		if !hasExplicitSelection {
			return fmt.Errorf("bun installer failed: %w", err)
		}
		fmt.Fprintf(cmd.ErrOrStderr(), "Bun installer failed (%v)\n", err)
		fmt.Fprintln(cmd.ErrOrStderr(), "Falling back to embedded installer (Claude Code + OpenCode only).")
		fmt.Fprintln(cmd.ErrOrStderr())
		return runEmbeddedInstaller(cmd, agentFlag, scopeFlag, uninstall)
	}

	// Bun unavailable: use embedded fallback.
	fmt.Fprintln(cmd.ErrOrStderr(), "Bun not found — using embedded fallback installer (Claude Code + OpenCode only).")
	fmt.Fprintln(cmd.ErrOrStderr(), "Install Bun for the full interactive experience with Cursor support.")
	fmt.Fprintln(cmd.ErrOrStderr())

	return runEmbeddedInstaller(cmd, agentFlag, scopeFlag, uninstall)
}

// runBunInstaller executes the TS interactive installer via bunx.
func runBunInstaller(
	cmd *cobra.Command,
	bunPath string,
	agentFlag []string,
	scopeFlag string,
	agentFlagChanged bool,
	scopeFlagChanged bool,
	uninstall bool,
) error {
	args := []string{"x", "@context-grabber/agent-skills"}
	if uninstall {
		args = append(args, "--uninstall")
	}
	if agentFlagChanged {
		agents := normalizeAgentValues(agentFlag)
		for _, agent := range agents {
			args = append(args, "--agent", agent)
		}
	}
	if scopeFlagChanged {
		args = append(args, "--scope", strings.TrimSpace(scopeFlag))
	}
	if agentFlagChanged || scopeFlagChanged {
		// Explicit flags indicate non-interactive intent.
		args = append(args, "--yes")
	}

	proc := exec.Command(bunPath, args...)
	proc.Stdin = os.Stdin
	proc.Stdout = cmd.OutOrStdout()
	proc.Stderr = cmd.ErrOrStderr()

	if err := proc.Run(); err != nil {
		return fmt.Errorf("interactive installer failed: %w", err)
	}
	return nil
}

func normalizeAgentValues(agentFlag []string) []string {
	seen := make(map[string]bool)
	var agents []string
	for _, raw := range agentFlag {
		for _, part := range strings.Split(raw, ",") {
			value := strings.ToLower(strings.TrimSpace(part))
			if value == "" || seen[value] {
				continue
			}
			seen[value] = true
			agents = append(agents, value)
		}
	}
	return agents
}

// runEmbeddedInstaller uses go:embed skill files as a non-interactive fallback.
func runEmbeddedInstaller(cmd *cobra.Command, agentFlag []string, scopeFlag string, uninstall bool) error {
	scope, err := skills.ValidateScope(scopeFlag)
	if err != nil {
		return err
	}

	agents, err := resolveAgents(agentFlag)
	if err != nil {
		return err
	}

	cwd, err := os.Getwd()
	if err != nil {
		return fmt.Errorf("could not determine working directory: %w", err)
	}

	w := cmd.OutOrStdout()
	action := "Installing for"
	doneVerb := "Created"
	if uninstall {
		action = "Uninstalling from"
		doneVerb = "Removed"
	}

	var results []skills.InstallResult
	if uninstall {
		results, err = skills.Uninstall(agents, scope, cwd)
	} else {
		results, err = skills.Install(agents, scope, cwd)
	}
	if err != nil {
		return err
	}

	fmt.Fprintln(w)
	for _, r := range results {
		label := agentLabel(r.Agent)
		fmt.Fprintf(w, "%s %s (%s scope)...\n", action, label, r.Scope)
		for _, p := range r.Paths {
			fmt.Fprintf(w, "  %s %s\n", doneVerb, p)
		}
		for _, s := range r.Symlinks {
			if uninstall {
				fmt.Fprintf(w, "  Removed symlink %s\n", s)
			} else {
				fmt.Fprintf(w, "  Symlinked %s\n", s)
			}
		}
		if len(r.Paths) == 0 && len(r.Symlinks) == 0 {
			fmt.Fprintf(w, "  Nothing to %s.\n", map[bool]string{true: "uninstall", false: "install"}[uninstall])
		}
	}

	fmt.Fprintln(w)
	if uninstall {
		fmt.Fprintln(w, "Done. Skill files removed.")
	} else {
		fmt.Fprintln(w, "Done. The agent can now discover and use cgrab.")
	}
	return nil
}

// resolveAgents parses the --agent flag values into validated AgentTargets.
// If no agents specified, defaults to all embedded agents.
func resolveAgents(agentFlag []string) ([]skills.AgentTarget, error) {
	if len(agentFlag) == 0 {
		return skills.EmbeddedAgents, nil
	}

	seen := make(map[skills.AgentTarget]bool)
	var agents []skills.AgentTarget
	for _, raw := range agentFlag {
		// Support comma-separated: --agent claude,opencode
		for _, s := range strings.Split(raw, ",") {
			s = strings.TrimSpace(s)
			if s == "" {
				continue
			}
			agent, err := skills.ValidateAgent(s)
			if err != nil {
				return nil, err
			}
			if seen[agent] {
				continue
			}
			seen[agent] = true
			agents = append(agents, agent)
		}
	}

	if len(agents) == 0 {
		return skills.EmbeddedAgents, nil
	}
	return agents, nil
}

// agentLabel returns a display-friendly name for an agent target.
func agentLabel(a skills.AgentTarget) string {
	switch a {
	case skills.AgentClaude:
		return "Claude Code"
	case skills.AgentOpenCode:
		return "OpenCode"
	default:
		return string(a)
	}
}

// resolveBunPathForSkills checks if Bun is available.
func resolveBunPathForSkills() string {
	if explicit := strings.TrimSpace(os.Getenv("CONTEXT_GRABBER_BUN_BIN")); explicit != "" {
		if _, err := os.Stat(explicit); err == nil {
			return explicit
		}
		return ""
	}
	path, err := exec.LookPath("bun")
	if err != nil {
		return ""
	}
	return path
}
