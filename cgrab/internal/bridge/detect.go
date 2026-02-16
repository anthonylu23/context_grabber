package bridge

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

const expectedProtocolVersion = "1"

var installedHostBinaryPath = "/Applications/ContextGrabber.app/Contents/MacOS/ContextGrabberHost"

type BridgeStatus struct {
	Target string `json:"target"`
	Status string `json:"status"`
	Detail string `json:"detail,omitempty"`
}

type DoctorReport struct {
	OverallStatus       string         `json:"overallStatus"`
	RepoRoot            string         `json:"repoRoot,omitempty"`
	OsaScriptAvailable  bool           `json:"osascriptAvailable"`
	BunAvailable        bool           `json:"bunAvailable"`
	HostBinaryAvailable bool           `json:"hostBinaryAvailable"`
	HostBinaryPath      string         `json:"hostBinaryPath,omitempty"`
	Bridges             []BridgeStatus `json:"bridges"`
	Warnings            []string       `json:"warnings,omitempty"`
}

type pingResponse struct {
	OK              bool   `json:"ok"`
	ProtocolVersion string `json:"protocolVersion"`
}

type commandRunner interface {
	Run(ctx context.Context, dir string, name string, args ...string) (stdout string, stderr string, err error)
}

type defaultCommandRunner struct{}

func (defaultCommandRunner) Run(ctx context.Context, dir string, name string, args ...string) (string, string, error) {
	cmd := exec.CommandContext(ctx, name, args...)
	cmd.Dir = dir
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

var runner commandRunner = defaultCommandRunner{}

func setRunnerForTesting(mock commandRunner) func() {
	previous := runner
	runner = mock
	return func() {
		runner = previous
	}
}

func RunDoctor(ctx context.Context) (DoctorReport, error) {
	var report DoctorReport
	repoRoot, repoErr := resolveRepoRoot()
	if repoErr != nil {
		report.Warnings = append(
			report.Warnings,
			fmt.Sprintf(
				"repository root not resolved (%v); browser bridge diagnostics need CONTEXT_GRABBER_REPO_ROOT outside the repo",
				repoErr,
			),
		)
	} else {
		report.RepoRoot = repoRoot
	}

	osaPath := resolveOsaScriptPath()
	report.OsaScriptAvailable = isExecutableFile(osaPath)
	if !report.OsaScriptAvailable {
		report.Warnings = append(report.Warnings, fmt.Sprintf("osascript not executable: %s", osaPath))
	}

	bunPath, bunOK := resolveBunPath()
	report.BunAvailable = bunOK
	if !bunOK {
		report.Warnings = append(report.Warnings, "bun not found; browser capture commands will be unavailable")
	}

	hostPath, hostOK := resolveHostBinaryPath(repoRoot)
	report.HostBinaryAvailable = hostOK
	report.HostBinaryPath = hostPath
	if !hostOK {
		report.Warnings = append(
			report.Warnings,
			"ContextGrabberHost binary not found; build apps/macos-host, install ContextGrabber.app, or set CONTEXT_GRABBER_HOST_BIN",
		)
	}

	report.Bridges = checkBrowserBridges(ctx, repoRoot, repoErr, bunPath, bunOK)

	anyReadyBridge := false
	for _, bridgeStatus := range report.Bridges {
		if bridgeStatus.Status == "ready" {
			anyReadyBridge = true
			break
		}
	}
	if anyReadyBridge || report.HostBinaryAvailable {
		report.OverallStatus = "ready"
	} else {
		report.OverallStatus = "unreachable"
	}

	return report, nil
}

func checkBrowserBridges(
	ctx context.Context,
	repoRoot string,
	repoErr error,
	bunPath string,
	bunOK bool,
) []BridgeStatus {
	targets := []struct {
		target      string
		packagePath string
	}{
		{target: "safari", packagePath: "packages/extension-safari"},
		{target: "chrome", packagePath: "packages/extension-chrome"},
	}

	statuses := make([]BridgeStatus, 0, len(targets))
	for _, target := range targets {
		if repoErr != nil {
			statuses = append(statuses, BridgeStatus{
				Target: target.target,
				Status: "unreachable",
				Detail: "repository root not resolved",
			})
			continue
		}
		if !bunOK {
			statuses = append(statuses, BridgeStatus{
				Target: target.target,
				Status: "unreachable",
				Detail: "bun not available",
			})
			continue
		}
		statuses = append(statuses, pingBridge(ctx, repoRoot, bunPath, target.target, target.packagePath))
	}
	return statuses
}

func pingBridge(ctx context.Context, repoRoot string, bunPath string, target string, packagePath string) BridgeStatus {
	packageDir := filepath.Join(repoRoot, packagePath)
	manifest := filepath.Join(packageDir, "package.json")
	if _, err := os.Stat(manifest); err != nil {
		return BridgeStatus{
			Target: target,
			Status: "unreachable",
			Detail: fmt.Sprintf("package not found: %s", packagePath),
		}
	}

	stdout, stderr, err := runner.Run(
		ctx,
		packageDir,
		bunPath,
		"src/native-messaging-cli.ts",
		"--ping",
	)
	if err != nil {
		message := strings.TrimSpace(stderr)
		if message == "" {
			message = strings.TrimSpace(stdout)
		}
		if message == "" {
			message = err.Error()
		}
		return BridgeStatus{
			Target: target,
			Status: "unreachable",
			Detail: message,
		}
	}

	var ping pingResponse
	if parseErr := json.Unmarshal([]byte(strings.TrimSpace(stdout)), &ping); parseErr != nil {
		return BridgeStatus{
			Target: target,
			Status: "unreachable",
			Detail: fmt.Sprintf("invalid ping response: %v", parseErr),
		}
	}

	if !ping.OK {
		return BridgeStatus{
			Target: target,
			Status: "unreachable",
			Detail: "bridge reported not ready",
		}
	}
	if ping.ProtocolVersion != expectedProtocolVersion {
		return BridgeStatus{
			Target: target,
			Status: "protocol_mismatch",
			Detail: fmt.Sprintf("bridge protocol=%s expected=%s", ping.ProtocolVersion, expectedProtocolVersion),
		}
	}
	return BridgeStatus{
		Target: target,
		Status: "ready",
		Detail: fmt.Sprintf("protocol=%s", ping.ProtocolVersion),
	}
}

func resolveRepoRoot() (string, error) {
	if explicit := strings.TrimSpace(os.Getenv("CONTEXT_GRABBER_REPO_ROOT")); explicit != "" {
		if hasRepoMarker(explicit) {
			return explicit, nil
		}
		return "", fmt.Errorf("CONTEXT_GRABBER_REPO_ROOT is set but invalid: %s", explicit)
	}

	currentDirectory, err := os.Getwd()
	if err != nil {
		return "", fmt.Errorf("resolve cwd: %w", err)
	}

	search := currentDirectory
	for i := 0; i < 12; i++ {
		if hasRepoMarker(search) {
			return search, nil
		}
		parent := filepath.Dir(search)
		if parent == search {
			break
		}
		search = parent
	}
	return "", fmt.Errorf("repository root not found from %s", currentDirectory)
}

func hasRepoMarker(root string) bool {
	marker := filepath.Join(root, "packages", "shared-types", "package.json")
	_, err := os.Stat(marker)
	return err == nil
}

func resolveOsaScriptPath() string {
	if explicit := strings.TrimSpace(os.Getenv("CONTEXT_GRABBER_OSASCRIPT_BIN")); explicit != "" {
		return explicit
	}
	return "/usr/bin/osascript"
}

func resolveBunPath() (string, bool) {
	if explicit := strings.TrimSpace(os.Getenv("CONTEXT_GRABBER_BUN_BIN")); explicit != "" {
		if isExecutableFile(explicit) {
			return explicit, true
		}
		return "", false
	}
	path, err := exec.LookPath("bun")
	if err != nil {
		return "", false
	}
	return path, true
}

func resolveHostBinaryPath(repoRoot string) (string, bool) {
	if explicit := strings.TrimSpace(os.Getenv("CONTEXT_GRABBER_HOST_BIN")); explicit != "" {
		return explicit, isExecutableFile(explicit)
	}

	candidates := make([]string, 0, 2)
	if strings.TrimSpace(repoRoot) != "" {
		candidates = append(
			candidates,
			filepath.Join(repoRoot, "apps", "macos-host", ".build", "debug", "ContextGrabberHost"),
		)
	}
	candidates = append(candidates, installedHostBinaryPath)

	for _, candidate := range candidates {
		if isExecutableFile(candidate) {
			return candidate, true
		}
	}
	return candidates[0], false
}

func isExecutableFile(path string) bool {
	info, err := os.Stat(path)
	if err != nil {
		return false
	}
	if info.IsDir() {
		return false
	}
	return info.Mode()&0o111 != 0
}
