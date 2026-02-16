package bridge

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
)

type BrowserTarget string

const (
	BrowserTargetSafari BrowserTarget = "safari"
	BrowserTargetChrome BrowserTarget = "chrome"
)

type BrowserCaptureSource string

const (
	BrowserCaptureSourceAuto    BrowserCaptureSource = "auto"
	BrowserCaptureSourceLive    BrowserCaptureSource = "live"
	BrowserCaptureSourceRuntime BrowserCaptureSource = "runtime"
)

type BrowserCaptureMetadata struct {
	Title         string
	URL           string
	SiteName      string
	ChromeAppName string
}

type BrowserCaptureAttempt struct {
	ExtractionMethod string                 `json:"extractionMethod"`
	Warnings         []string               `json:"warnings"`
	ErrorCode        string                 `json:"errorCode,omitempty"`
	Markdown         string                 `json:"markdown"`
	Payload          map[string]any         `json:"payload"`
	Normalized       map[string]any         `json:"normalizedContext,omitempty"`
	Response         map[string]any         `json:"response,omitempty"`
	Request          map[string]any         `json:"request,omitempty"`
	Raw              map[string]interface{} `json:"-"`
}

type browserCaptureRunner interface {
	Run(
		ctx context.Context,
		dir string,
		name string,
		args []string,
		env []string,
	) (stdout string, stderr string, err error)
}

type defaultBrowserCaptureRunner struct{}

func (defaultBrowserCaptureRunner) Run(
	ctx context.Context,
	dir string,
	name string,
	args []string,
	env []string,
) (string, string, error) {
	cmd := exec.CommandContext(ctx, name, args...)
	cmd.Dir = dir
	cmd.Env = env
	var stdout bytes.Buffer
	var stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	err := cmd.Run()
	return stdout.String(), stderr.String(), err
}

var bunCaptureRunner browserCaptureRunner = defaultBrowserCaptureRunner{}

func setBunCaptureRunnerForTesting(mock browserCaptureRunner) func() {
	previous := bunCaptureRunner
	bunCaptureRunner = mock
	return func() {
		bunCaptureRunner = previous
	}
}

func CaptureBrowser(
	ctx context.Context,
	target BrowserTarget,
	source BrowserCaptureSource,
	timeoutMs int,
	metadata BrowserCaptureMetadata,
) (BrowserCaptureAttempt, error) {
	if timeoutMs <= 0 {
		timeoutMs = 1200
	}
	if source == "" {
		source = BrowserCaptureSourceAuto
	}
	if target != BrowserTargetSafari && target != BrowserTargetChrome {
		return BrowserCaptureAttempt{}, fmt.Errorf("unsupported browser target: %s", target)
	}
	switch source {
	case BrowserCaptureSourceAuto, BrowserCaptureSourceLive, BrowserCaptureSourceRuntime:
	default:
		return BrowserCaptureAttempt{}, fmt.Errorf("unsupported browser capture source: %s", source)
	}

	repoRoot, err := resolveRepoRoot()
	if err != nil {
		return BrowserCaptureAttempt{}, err
	}

	bunPath, bunOK := resolveBunPath()
	if !bunOK {
		return BrowserCaptureAttempt{}, fmt.Errorf("bun not found; browser capture is unavailable")
	}

	scriptPath := filepath.Join(repoRoot, "cgrab", "internal", "bridge", "browser_capture.ts")
	if _, statErr := os.Stat(scriptPath); statErr != nil {
		return BrowserCaptureAttempt{}, fmt.Errorf("browser capture bridge script not found: %s", scriptPath)
	}

	args := []string{
		scriptPath,
		"--target",
		string(target),
		"--source",
		string(source),
		"--timeout-ms",
		strconv.Itoa(timeoutMs),
	}
	if title := strings.TrimSpace(metadata.Title); title != "" {
		args = append(args, "--title", title)
	}
	if url := strings.TrimSpace(metadata.URL); url != "" {
		args = append(args, "--url", url)
	}
	if siteName := strings.TrimSpace(metadata.SiteName); siteName != "" {
		args = append(args, "--site-name", siteName)
	}
	if target == BrowserTargetChrome {
		if chromeAppName := strings.TrimSpace(metadata.ChromeAppName); chromeAppName != "" {
			args = append(args, "--chrome-app-name", chromeAppName)
		}
	}

	env := append([]string{}, os.Environ()...)
	env = append(env, "CONTEXT_GRABBER_REPO_ROOT="+repoRoot)
	env = append(env, "CONTEXT_GRABBER_BUN_BIN="+bunPath)
	stdout, stderr, runErr := bunCaptureRunner.Run(ctx, repoRoot, bunPath, args, env)
	if runErr != nil {
		detail := strings.TrimSpace(stderr)
		if detail == "" {
			detail = strings.TrimSpace(stdout)
		}
		if detail == "" {
			detail = runErr.Error()
		}
		return BrowserCaptureAttempt{}, fmt.Errorf("browser capture bridge failed for %s: %s", target, detail)
	}

	trimmed := strings.TrimSpace(stdout)
	if trimmed == "" {
		return BrowserCaptureAttempt{}, fmt.Errorf("browser capture bridge returned empty output for %s", target)
	}

	var attempt BrowserCaptureAttempt
	if err := json.Unmarshal([]byte(trimmed), &attempt); err != nil {
		return BrowserCaptureAttempt{}, fmt.Errorf("invalid browser capture response for %s: %w", target, err)
	}

	if attempt.Warnings == nil {
		attempt.Warnings = []string{}
	}
	return attempt, nil
}
