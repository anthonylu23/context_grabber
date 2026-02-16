package bridge

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"testing"
)

func TestEnsureHostAppRunningNoopWhenAlreadyRunning(t *testing.T) {
	restore := setRunnerForTesting(mockCommandRunner(func(
		_ context.Context,
		_ string,
		name string,
		args ...string,
	) (string, string, error) {
		if name == "pgrep" && len(args) >= 2 && args[1] == "ContextGrabberHost" {
			return "123\n", "", nil
		}
		return "", "", errors.New("unexpected")
	}))
	defer restore()

	launched, err := EnsureHostAppRunning(context.Background())
	if err != nil {
		t.Fatalf("EnsureHostAppRunning returned error: %v", err)
	}
	if launched {
		t.Fatalf("expected launched=false when app already running")
	}
}

func TestEnsureHostAppRunningLaunchesInstalledApp(t *testing.T) {
	appBundlePath := filepath.Join(t.TempDir(), "ContextGrabber.app")
	if err := os.MkdirAll(appBundlePath, 0o755); err != nil {
		t.Fatalf("mkdir app bundle path failed: %v", err)
	}

	t.Setenv("CONTEXT_GRABBER_APP_BUNDLE_PATH", appBundlePath)
	t.Setenv("CONTEXT_GRABBER_HOST_BIN", filepath.Join(t.TempDir(), "missing", "ContextGrabberHost"))

	launchCalled := false
	restore := setRunnerForTesting(mockCommandRunner(func(
		_ context.Context,
		_ string,
		name string,
		args ...string,
	) (string, string, error) {
		switch name {
		case "pgrep":
			if launchCalled {
				return "123\n", "", nil
			}
			return "", "", errors.New("process not found")
		case "open":
			if len(args) != 1 || args[0] != appBundlePath {
				t.Fatalf("unexpected open args: %#v", args)
			}
			launchCalled = true
			return "", "", nil
		default:
			return "", "", errors.New("unexpected command")
		}
	}))
	defer restore()

	launched, err := EnsureHostAppRunning(context.Background())
	if err != nil {
		t.Fatalf("EnsureHostAppRunning returned error: %v", err)
	}
	if !launched {
		t.Fatalf("expected launched=true when app was not running")
	}
	if !launchCalled {
		t.Fatalf("expected app launch command to be called")
	}
}
