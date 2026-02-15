package cmd

import "testing"

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

	for _, expected := range []string{"list", "capture", "doctor"} {
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
