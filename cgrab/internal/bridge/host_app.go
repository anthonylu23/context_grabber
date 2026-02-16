package bridge

import (
	"context"
	"fmt"
	"io"
	"os"
	"os/exec"
	"strings"
	"time"
)

const hostAppBundlePathEnvVar = "CONTEXT_GRABBER_APP_BUNDLE_PATH"

var (
	installedHostAppBundlePath = "/Applications/ContextGrabber.app"
	hostAppLaunchTimeout       = 4 * time.Second
)

func EnsureHostAppRunning(ctx context.Context) (bool, error) {
	if hostAppRunning(ctx) {
		return false, nil
	}

	hostBinaryPath, hostBinaryOK := resolveHostBinaryPathForLaunch()
	if err := launchHostApp(ctx, hostBinaryPath, hostBinaryOK); err != nil {
		return false, err
	}

	deadline := time.Now().Add(hostAppLaunchTimeout)
	for time.Now().Before(deadline) {
		if hostAppRunning(ctx) {
			return true, nil
		}
		select {
		case <-ctx.Done():
			return true, ctx.Err()
		case <-time.After(120 * time.Millisecond):
		}
	}

	return true, fmt.Errorf("context grabber app did not become ready before timeout")
}

func resolveHostAppBundlePath() string {
	if override := strings.TrimSpace(os.Getenv(hostAppBundlePathEnvVar)); override != "" {
		return override
	}
	return installedHostAppBundlePath
}

func resolveHostBinaryPathForLaunch() (string, bool) {
	repoRoot, _ := resolveRepoRoot()
	return resolveHostBinaryPath(repoRoot)
}

func launchHostApp(ctx context.Context, hostBinaryPath string, hostBinaryOK bool) error {
	bundlePath := resolveHostAppBundlePath()
	if bundlePath != "" {
		info, err := os.Stat(bundlePath)
		if err == nil && info.IsDir() {
			if _, stderr, openErr := runner.Run(ctx, "", "open", bundlePath); openErr == nil {
				return nil
			} else {
				message := strings.TrimSpace(stderr)
				if hostBinaryOK {
					if launchErr := launchHostBinaryDetached(hostBinaryPath); launchErr == nil {
						return nil
					}
				}
				if message != "" {
					return fmt.Errorf("open app bundle failed: %s", message)
				}
				return fmt.Errorf("open app bundle failed: %w", openErr)
			}
		}
	}

	if hostBinaryOK {
		if err := launchHostBinaryDetached(hostBinaryPath); err != nil {
			return fmt.Errorf("launch host binary failed: %w", err)
		}
		return nil
	}

	return fmt.Errorf(
		"unable to launch ContextGrabber app; set %s or install ContextGrabber.app",
		hostAppBundlePathEnvVar,
	)
}

func launchHostBinaryDetached(hostBinaryPath string) error {
	cmd := exec.Command(hostBinaryPath)
	cmd.Stdout = io.Discard
	cmd.Stderr = io.Discard
	if err := cmd.Start(); err != nil {
		return err
	}
	go func() {
		_ = cmd.Wait()
	}()
	return nil
}

func hostAppRunning(ctx context.Context) bool {
	for _, processName := range []string{"ContextGrabberHost", "ContextGrabber"} {
		if _, _, err := runner.Run(ctx, "", "pgrep", "-x", processName); err == nil {
			return true
		}
	}
	return false
}
