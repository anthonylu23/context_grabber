package cmd

import (
	"bytes"
	"strings"
	"testing"
)

func TestDefaultGlobalOptionsReturnsIndependentInstances(t *testing.T) {
	first := defaultGlobalOptions()
	second := defaultGlobalOptions()

	first.format = formatJSON
	first.outputFile = "/tmp/out.json"
	first.clipboard = true

	if second.format != formatMarkdown {
		t.Fatalf("expected second format to remain %q, got %q", formatMarkdown, second.format)
	}
	if second.outputFile != "" {
		t.Fatalf("expected second outputFile to remain empty, got %q", second.outputFile)
	}
	if second.clipboard {
		t.Fatalf("expected second clipboard to remain false")
	}
}

func TestRootCommandRegistersCaptureCommands(t *testing.T) {
	root := newRootCommand()
	if root == nil {
		t.Fatalf("expected root command")
	}

	commandNames := map[string]bool{}
	for _, command := range root.Commands() {
		commandNames[command.Name()] = true
	}

	for _, expected := range []string{"list", "capture", "doctor", "config", "docs"} {
		if !commandNames[expected] {
			t.Fatalf("expected root command to register %q", expected)
		}
	}
}

func TestRootCommandUseIsCgrab(t *testing.T) {
	root := newRootCommand()
	if root == nil {
		t.Fatalf("expected root command")
	}

	if root.Use != "cgrab" {
		t.Fatalf("expected root Use to be cgrab, got %q", root.Use)
	}
}

func TestRootCommandShortName(t *testing.T) {
	root := newRootCommand()
	if root == nil {
		t.Fatalf("expected root command")
	}
	if root.Short != "Context Grabber CLI" {
		t.Fatalf("unexpected root short description: %q", root.Short)
	}
}

func TestRootHelpIncludesProductCard(t *testing.T) {
	command := newRootCommand()
	var stdout bytes.Buffer
	var stderr bytes.Buffer
	command.SetOut(&stdout)
	command.SetErr(&stderr)
	command.SetArgs([]string{"--help"})

	if err := command.Execute(); err != nil {
		t.Fatalf("root help returned error: %v", err)
	}

	output := stdout.String() + stderr.String()
	if !strings.Contains(output, "ContextGrabber") {
		t.Fatalf("expected product card title in help output:\n%s", output)
	}
	if !strings.Contains(output, "base_dir") {
		t.Fatalf("expected product card config rows in help output:\n%s", output)
	}
}

func TestSubcommandHelpOmitsProductCard(t *testing.T) {
	command := newRootCommand()
	var stdout bytes.Buffer
	var stderr bytes.Buffer
	command.SetOut(&stdout)
	command.SetErr(&stderr)
	command.SetArgs([]string{"capture", "--help"})

	if err := command.Execute(); err != nil {
		t.Fatalf("capture help returned error: %v", err)
	}

	output := stdout.String() + stderr.String()
	if strings.Contains(output, "ContextGrabber") {
		t.Fatalf("did not expect product card title in subcommand help:\n%s", output)
	}
}

func TestBuildProductCardHandlesNarrowWidths(t *testing.T) {
	rendered := buildProductCard(20)
	if strings.TrimSpace(rendered) == "" {
		t.Fatalf("expected non-empty card for narrow width")
	}
	if !strings.Contains(rendered, "base_dir") {
		t.Fatalf("expected config row in narrow card output:\n%s", rendered)
	}
	if strings.Contains(rendered, "╭") || strings.Contains(rendered, "╰") {
		t.Fatalf("expected narrow card fallback without borders:\n%s", rendered)
	}
}

func TestBuildProductCardUsesBorderOnWideWidths(t *testing.T) {
	rendered := buildProductCard(70)
	if !strings.Contains(rendered, "╭") || !strings.Contains(rendered, "╰") {
		t.Fatalf("expected bordered card for wide width:\n%s", rendered)
	}
}
