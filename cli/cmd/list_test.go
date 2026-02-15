package cmd

import (
	"bytes"
	"testing"
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
