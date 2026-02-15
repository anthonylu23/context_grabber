package cmd

import (
	"bytes"
	"context"
	"fmt"
	"strings"
	"testing"
)

func TestDocsCommandPrintsURLWhenOpenFails(t *testing.T) {
	previousOpenURLFunc := openURLFunc
	t.Cleanup(func() {
		openURLFunc = previousOpenURLFunc
	})
	openURLFunc = func(_ context.Context, _ string) error {
		return fmt.Errorf("open failed")
	}

	command := newDocsCommand()
	var stdout bytes.Buffer
	var stderr bytes.Buffer
	command.SetOut(&stdout)
	command.SetErr(&stderr)

	if err := command.Execute(); err != nil {
		t.Fatalf("newDocsCommand Execute returned error: %v", err)
	}
	if !strings.Contains(stdout.String(), repoDocsURL) {
		t.Fatalf("expected stdout to include docs URL, got %q", stdout.String())
	}
	if !strings.Contains(stderr.String(), "warning: could not open browser") {
		t.Fatalf("expected warning in stderr, got %q", stderr.String())
	}
}
