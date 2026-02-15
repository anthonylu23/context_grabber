package osascript

import (
	"context"
	"strings"
	"testing"
)

func TestActivateTabRejectsUnsupportedBrowser(t *testing.T) {
	err := ActivateTab(context.Background(), "firefox", 1, 1)
	if err == nil {
		t.Fatalf("expected error for unsupported browser")
	}
}

func TestActivateAppByNameRejectsEmptyName(t *testing.T) {
	err := ActivateAppByName(context.Background(), "   ")
	if err == nil {
		t.Fatalf("expected error for empty app name")
	}
}

func TestActivateTabPassesTabIndexesToOsaScript(t *testing.T) {
	restore := setRunnerForTesting(mockScriptRunner(func(_ context.Context, _ string, args ...string) (string, string, error) {
		joined := strings.Join(args, " ")
		if !strings.Contains(joined, "2") || !strings.Contains(joined, "5") {
			t.Fatalf("expected osascript args to include window/tab indexes, got %q", joined)
		}
		return "", "", nil
	}))
	defer restore()

	if err := ActivateTab(context.Background(), "safari", 2, 5); err != nil {
		t.Fatalf("ActivateTab returned error: %v", err)
	}
}
