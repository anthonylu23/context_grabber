package osascript

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"strings"
)

const (
	fieldSeparator  = "\x1e"
	recordSeparator = "\x1f"
)

type scriptRunner interface {
	Run(ctx context.Context, name string, args ...string) (stdout string, stderr string, err error)
}

type defaultScriptRunner struct{}

func (defaultScriptRunner) Run(ctx context.Context, name string, args ...string) (string, string, error) {
	cmd := exec.CommandContext(ctx, name, args...)
	stdoutBytes, err := cmd.Output()
	if err == nil {
		return string(stdoutBytes), "", nil
	}

	var stderr string
	if exitErr, ok := err.(*exec.ExitError); ok {
		stderr = string(exitErr.Stderr)
	}
	return string(stdoutBytes), stderr, err
}

var runner scriptRunner = defaultScriptRunner{}

func setRunnerForTesting(mock scriptRunner) func() {
	previous := runner
	runner = mock
	return func() {
		runner = previous
	}
}

func runAppleScript(ctx context.Context, script string) (string, error) {
	return runAppleScriptWithArgs(ctx, script)
}

func runAppleScriptWithArgs(ctx context.Context, script string, scriptArgs ...string) (string, error) {
	osaPath := resolveOsaScriptPath()
	args := []string{"-e", script}
	args = append(args, scriptArgs...)
	stdout, stderr, err := runner.Run(ctx, osaPath, args...)
	if err != nil {
		message := strings.TrimSpace(stderr)
		if message == "" {
			message = strings.TrimSpace(stdout)
		}
		if message != "" {
			return "", fmt.Errorf("osascript execution failed: %s", message)
		}
		return "", fmt.Errorf("osascript execution failed: %w", err)
	}
	return strings.TrimSpace(stdout), nil
}

func resolveOsaScriptPath() string {
	if configured := strings.TrimSpace(os.Getenv("CONTEXT_GRABBER_OSASCRIPT_BIN")); configured != "" {
		return configured
	}
	return "/usr/bin/osascript"
}
