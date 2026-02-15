package cmd

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/anthonylu23/context_grabber/cgrab/internal/osascript"
)

func TestWriteWarningsEmitsEachWarningOnOwnLine(t *testing.T) {
	var stderr bytes.Buffer
	writeWarnings(&stderr, []string{
		"safari tabs unavailable: timed out",
		"chrome tabs unavailable: bridge unavailable",
	})

	got := stderr.String()
	want := "" +
		"warning: safari tabs unavailable: timed out\n" +
		"warning: chrome tabs unavailable: bridge unavailable\n"
	if got != want {
		t.Fatalf("unexpected warnings output:\nwant: %q\ngot:  %q", want, got)
	}
}

func TestWriteWarningsNoopWhenEmpty(t *testing.T) {
	var stderr bytes.Buffer
	writeWarnings(&stderr, nil)
	if stderr.Len() != 0 {
		t.Fatalf("expected empty warnings output, got %q", stderr.String())
	}
}

func TestListDefaultsToTabsAndAppsJSON(t *testing.T) {
	restore := stubListSources(
		func(_ context.Context, _ string) ([]osascript.TabEntry, []string, error) {
			return []osascript.TabEntry{
				{Browser: "safari", WindowIndex: 1, TabIndex: 1, IsActive: true, Title: "Doc", URL: "https://example.com"},
			}, nil, nil
		},
		func(_ context.Context) ([]osascript.AppEntry, error) {
			return []osascript.AppEntry{
				{AppName: "Finder", BundleIdentifier: "com.apple.finder", WindowCount: 1},
			}, nil
		},
	)
	defer restore()

	payloadBytes, _, err := runRootCommandToFile(t, "list", "--format", "json")
	if err != nil {
		t.Fatalf("list returned error: %v", err)
	}

	var payload struct {
		Tabs []osascript.TabEntry `json:"tabs"`
		Apps []osascript.AppEntry `json:"apps"`
	}
	if unmarshalErr := json.Unmarshal(payloadBytes, &payload); unmarshalErr != nil {
		t.Fatalf("invalid JSON payload: %v\noutput:\n%s", unmarshalErr, string(payloadBytes))
	}
	if len(payload.Tabs) != 1 || payload.Tabs[0].Browser != "safari" {
		t.Fatalf("unexpected tabs payload: %+v", payload.Tabs)
	}
	if len(payload.Apps) != 1 || payload.Apps[0].AppName != "Finder" {
		t.Fatalf("unexpected apps payload: %+v", payload.Apps)
	}
}

func TestListTabsOnlySkipsAppsSource(t *testing.T) {
	appCalls := 0
	restore := stubListSources(
		func(_ context.Context, browser string) ([]osascript.TabEntry, []string, error) {
			if browser != "chrome" {
				t.Fatalf("expected browser filter chrome, got %q", browser)
			}
			return []osascript.TabEntry{
				{Browser: "chrome", WindowIndex: 1, TabIndex: 1, IsActive: true, Title: "Issue", URL: "https://example.com/issue"},
			}, nil, nil
		},
		func(_ context.Context) ([]osascript.AppEntry, error) {
			appCalls++
			return nil, nil
		},
	)
	defer restore()

	payloadBytes, _, err := runRootCommandToFile(t, "list", "--tabs", "--browser", "chrome")
	if err != nil {
		t.Fatalf("list --tabs returned error: %v", err)
	}
	if appCalls != 0 {
		t.Fatalf("expected apps source to be skipped, got %d calls", appCalls)
	}
	output := string(payloadBytes)
	if strings.Contains(output, "Running Apps") {
		t.Fatalf("tabs-only output unexpectedly contains apps section:\n%s", output)
	}
	if !strings.Contains(output, "# Open Tabs") {
		t.Fatalf("tabs-only output missing tabs section:\n%s", output)
	}
}

func TestListAppsOnlySkipsTabsSource(t *testing.T) {
	tabCalls := 0
	restore := stubListSources(
		func(_ context.Context, _ string) ([]osascript.TabEntry, []string, error) {
			tabCalls++
			return nil, nil, nil
		},
		func(_ context.Context) ([]osascript.AppEntry, error) {
			return []osascript.AppEntry{
				{AppName: "Xcode", BundleIdentifier: "com.apple.dt.Xcode", WindowCount: 2},
			}, nil
		},
	)
	defer restore()

	payloadBytes, _, err := runRootCommandToFile(t, "list", "--apps")
	if err != nil {
		t.Fatalf("list --apps returned error: %v", err)
	}
	if tabCalls != 0 {
		t.Fatalf("expected tabs source to be skipped, got %d calls", tabCalls)
	}
	output := string(payloadBytes)
	if strings.Contains(output, "Open Tabs") {
		t.Fatalf("apps-only output unexpectedly contains tabs section:\n%s", output)
	}
	if !strings.Contains(output, "# Running Apps") {
		t.Fatalf("apps-only output missing apps section:\n%s", output)
	}
}

func TestListReturnsPartialOutputWithWarningsWhenOneSourceFails(t *testing.T) {
	restore := stubListSources(
		func(_ context.Context, _ string) ([]osascript.TabEntry, []string, error) {
			return nil, []string{"safari tabs unavailable: timed out"}, errors.New("unable to enumerate tabs from requested browsers")
		},
		func(_ context.Context) ([]osascript.AppEntry, error) {
			return []osascript.AppEntry{
				{AppName: "Finder", BundleIdentifier: "com.apple.finder", WindowCount: 1},
			}, nil
		},
	)
	defer restore()

	payloadBytes, stderr, err := runRootCommandToFile(t, "list")
	if err != nil {
		t.Fatalf("expected partial success, got error: %v", err)
	}
	output := string(payloadBytes)
	if !strings.Contains(output, "# Running Apps") {
		t.Fatalf("expected apps section in output:\n%s", output)
	}
	if !strings.Contains(stderr, "warning: safari tabs unavailable: timed out") {
		t.Fatalf("expected tab warning in stderr:\n%s", stderr)
	}
	if !strings.Contains(stderr, "warning: tabs failed:") {
		t.Fatalf("expected combined failure warning in stderr:\n%s", stderr)
	}
}

func stubListSources(
	tabs func(context.Context, string) ([]osascript.TabEntry, []string, error),
	apps func(context.Context) ([]osascript.AppEntry, error),
) func() {
	previousTabs := listTabsFunc
	previousApps := listAppsFunc
	listTabsFunc = tabs
	listAppsFunc = apps
	return func() {
		listTabsFunc = previousTabs
		listAppsFunc = previousApps
	}
}

func runRootCommand(args ...string) (stdout string, stderr string, err error) {
	command := newRootCommand()
	var out bytes.Buffer
	var errOut bytes.Buffer
	command.SetOut(&out)
	command.SetErr(&errOut)
	command.SetArgs(args)
	err = command.Execute()
	return out.String(), errOut.String(), err
}

func runRootCommandToFile(t *testing.T, args ...string) ([]byte, string, error) {
	t.Helper()
	outputPath := filepath.Join(t.TempDir(), "list-output.txt")
	argsWithFile := append(append([]string{}, args...), "--file", outputPath)
	_, stderr, err := runRootCommand(argsWithFile...)
	payload, readErr := os.ReadFile(outputPath)
	if err != nil {
		return nil, stderr, err
	}
	if readErr != nil {
		t.Fatalf("read output file failed: %v", readErr)
	}
	return payload, stderr, nil
}
