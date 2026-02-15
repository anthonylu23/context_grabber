package osascript

import (
	"context"
	"errors"
	"strings"
	"testing"
)

type mockScriptRunner func(ctx context.Context, name string, args ...string) (string, string, error)

func (m mockScriptRunner) Run(ctx context.Context, name string, args ...string) (string, string, error) {
	return m(ctx, name, args...)
}

func TestParseTabEntries(t *testing.T) {
	raw := strings.Join([]string{
		"1" + fieldSeparator + "1" + fieldSeparator + "true" + fieldSeparator + "Home" + fieldSeparator + "https://example.com",
		"1" + fieldSeparator + "2" + fieldSeparator + "false" + fieldSeparator + "Docs" + fieldSeparator + "https://example.com/docs",
	}, recordSeparator)

	entries, err := parseTabEntries("safari", raw)
	if err != nil {
		t.Fatalf("parseTabEntries returned error: %v", err)
	}
	if len(entries) != 2 {
		t.Fatalf("expected 2 entries, got %d", len(entries))
	}
	if !entries[0].IsActive || entries[0].Title != "Home" {
		t.Fatalf("unexpected first entry: %#v", entries[0])
	}
	if entries[1].IsActive {
		t.Fatalf("expected second entry inactive, got active")
	}
}

func TestListTabsPartialFailureStillReturnsSuccess(t *testing.T) {
	restore := setRunnerForTesting(mockScriptRunner(func(_ context.Context, _ string, args ...string) (string, string, error) {
		script := args[len(args)-1]
		if strings.Contains(script, `tell application "Safari"`) {
			record := "1" + fieldSeparator + "1" + fieldSeparator + "true" + fieldSeparator + "Home" + fieldSeparator + "https://example.com"
			return record, "", nil
		}
		if strings.Contains(script, `tell application "Google Chrome"`) {
			return "", "chrome bridge unavailable", errors.New("failed")
		}
		return "", "", nil
	}))
	defer restore()

	entries, warnings, err := ListTabs(context.Background(), "")
	if err != nil {
		t.Fatalf("expected partial success, got error: %v", err)
	}
	if len(entries) != 1 {
		t.Fatalf("expected one successful entry, got %d", len(entries))
	}
	if len(warnings) != 1 {
		t.Fatalf("expected one warning, got %d", len(warnings))
	}
}

func TestListTabsAllFailuresReturnError(t *testing.T) {
	restore := setRunnerForTesting(mockScriptRunner(func(_ context.Context, _ string, _ ...string) (string, string, error) {
		return "", "bridge unavailable", errors.New("failed")
	}))
	defer restore()

	_, warnings, err := ListTabs(context.Background(), "")
	if err == nil {
		t.Fatalf("expected error when all browsers fail")
	}
	if len(warnings) != 2 {
		t.Fatalf("expected warnings for safari and chrome, got %d", len(warnings))
	}
}
