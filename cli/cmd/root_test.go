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
