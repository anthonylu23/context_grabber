package bridge

import (
	"bytes"
	"context"
	"fmt"
	"os/exec"
	"strings"
)

type DesktopCaptureMethod string

const (
	DesktopCaptureMethodAuto DesktopCaptureMethod = "auto"
	DesktopCaptureMethodAX   DesktopCaptureMethod = "ax"
	DesktopCaptureMethodOCR  DesktopCaptureMethod = "ocr"
)

type DesktopCaptureFormat string

const (
	DesktopCaptureFormatMarkdown DesktopCaptureFormat = "markdown"
	DesktopCaptureFormatJSON     DesktopCaptureFormat = "json"
)

type DesktopCaptureRequest struct {
	AppName          string
	BundleIdentifier string
	Method           DesktopCaptureMethod
	Format           DesktopCaptureFormat
}

type desktopCaptureRunner interface {
	Run(ctx context.Context, name string, args []string) (stdout string, stderr string, err error)
}

type defaultDesktopCaptureRunner struct{}

func (defaultDesktopCaptureRunner) Run(
	ctx context.Context,
	name string,
	args []string,
) (string, string, error) {
	cmd := exec.CommandContext(ctx, name, args...)
	var stdout bytes.Buffer
	var stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	err := cmd.Run()
	return stdout.String(), stderr.String(), err
}

var swiftCaptureRunner desktopCaptureRunner = defaultDesktopCaptureRunner{}

func setSwiftCaptureRunnerForTesting(mock desktopCaptureRunner) func() {
	previous := swiftCaptureRunner
	swiftCaptureRunner = mock
	return func() {
		swiftCaptureRunner = previous
	}
}

func CaptureDesktop(ctx context.Context, request DesktopCaptureRequest) ([]byte, error) {
	if request.Method == "" {
		request.Method = DesktopCaptureMethodAuto
	}
	if request.Format == "" {
		request.Format = DesktopCaptureFormatMarkdown
	}

	switch request.Method {
	case DesktopCaptureMethodAuto, DesktopCaptureMethodAX, DesktopCaptureMethodOCR:
	default:
		return nil, fmt.Errorf("unsupported desktop capture method: %s", request.Method)
	}
	switch request.Format {
	case DesktopCaptureFormatMarkdown, DesktopCaptureFormatJSON:
	default:
		return nil, fmt.Errorf("unsupported desktop capture format: %s", request.Format)
	}
	if strings.TrimSpace(request.AppName) == "" && strings.TrimSpace(request.BundleIdentifier) == "" {
		return nil, fmt.Errorf("desktop capture requires app name or bundle identifier")
	}

	repoRoot, err := resolveRepoRoot()
	if err != nil {
		return nil, err
	}

	hostBinaryPath, hostBinaryOK := resolveHostBinaryPath(repoRoot)
	if !hostBinaryOK {
		return nil, fmt.Errorf("ContextGrabberHost binary not found; build apps/macos-host first")
	}

	args := []string{"--capture"}
	if appName := strings.TrimSpace(request.AppName); appName != "" {
		args = append(args, "--app", appName)
	}
	if bundleID := strings.TrimSpace(request.BundleIdentifier); bundleID != "" {
		args = append(args, "--bundle-id", bundleID)
	}
	args = append(args, "--method", string(request.Method))
	args = append(args, "--format", string(request.Format))

	stdout, stderr, runErr := swiftCaptureRunner.Run(ctx, hostBinaryPath, args)
	if runErr != nil {
		detail := strings.TrimSpace(stderr)
		if detail == "" {
			detail = strings.TrimSpace(stdout)
		}
		if detail == "" {
			detail = runErr.Error()
		}
		return nil, fmt.Errorf("desktop capture failed: %s", detail)
	}

	trimmed := strings.TrimSpace(stdout)
	if trimmed == "" {
		return nil, fmt.Errorf("desktop capture produced empty output")
	}

	return []byte(stdout), nil
}
