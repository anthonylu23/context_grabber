package osascript

import (
	"context"
	"strings"
	"testing"
)

func TestParseAppEntries(t *testing.T) {
	raw := strings.Join([]string{
		"Finder" + fieldSeparator + "com.apple.finder" + fieldSeparator + "3",
		"Terminal" + fieldSeparator + "com.apple.Terminal" + fieldSeparator + "1",
	}, recordSeparator)

	entries, err := parseAppEntries(raw)
	if err != nil {
		t.Fatalf("parseAppEntries returned error: %v", err)
	}
	if len(entries) != 2 {
		t.Fatalf("expected 2 entries, got %d", len(entries))
	}
	if entries[0].AppName != "Finder" || entries[0].WindowCount != 3 {
		t.Fatalf("unexpected first entry: %#v", entries[0])
	}
}

func TestListAppsReturnsSortedResults(t *testing.T) {
	restore := setRunnerForTesting(mockScriptRunner(func(_ context.Context, _ string, _ ...string) (string, string, error) {
		raw := strings.Join([]string{
			"Terminal" + fieldSeparator + "com.apple.Terminal" + fieldSeparator + "1",
			"Finder" + fieldSeparator + "com.apple.finder" + fieldSeparator + "2",
		}, recordSeparator)
		return raw, "", nil
	}))
	defer restore()

	entries, err := ListApps(context.Background())
	if err != nil {
		t.Fatalf("ListApps returned error: %v", err)
	}
	if len(entries) != 2 {
		t.Fatalf("expected 2 entries, got %d", len(entries))
	}
	if entries[0].AppName != "Finder" {
		t.Fatalf("expected Finder first after sorting, got %s", entries[0].AppName)
	}
}
