package config

import (
	"path/filepath"
	"testing"
)

func TestResolveBaseDirUsesOverride(t *testing.T) {
	override := filepath.Join(t.TempDir(), "contextgrabber")
	t.Setenv(cliHomeOverrideEnvVar, override)

	baseDir, err := ResolveBaseDir()
	if err != nil {
		t.Fatalf("ResolveBaseDir returned error: %v", err)
	}
	if baseDir != override {
		t.Fatalf("unexpected base dir: want=%q got=%q", override, baseDir)
	}
}

func TestResolveBaseDirRejectsRelativeOverride(t *testing.T) {
	t.Setenv(cliHomeOverrideEnvVar, "./relative")
	if _, err := ResolveBaseDir(); err == nil {
		t.Fatalf("expected error for relative override path")
	}
}

func TestSaveLoadAndResolveCaptureOutputDir(t *testing.T) {
	baseDir := filepath.Join(t.TempDir(), "contextgrabber")
	t.Setenv(cliHomeOverrideEnvVar, baseDir)

	if err := SaveSettings(Settings{CaptureOutputSubdir: "captures/team-a"}); err != nil {
		t.Fatalf("SaveSettings returned error: %v", err)
	}

	settings, err := LoadSettings()
	if err != nil {
		t.Fatalf("LoadSettings returned error: %v", err)
	}
	if settings.CaptureOutputSubdir != filepath.Join("captures", "team-a") {
		t.Fatalf("unexpected capture subdir: %q", settings.CaptureOutputSubdir)
	}

	outputDir, err := ResolveCaptureOutputDir(settings)
	if err != nil {
		t.Fatalf("ResolveCaptureOutputDir returned error: %v", err)
	}
	wantOutputDir := filepath.Join(baseDir, "captures", "team-a")
	if outputDir != wantOutputDir {
		t.Fatalf("unexpected output dir: want=%q got=%q", wantOutputDir, outputDir)
	}
}

func TestNormalizeCaptureSubdirRejectsParentTraversal(t *testing.T) {
	if _, err := normalizeCaptureSubdir("../outside"); err == nil {
		t.Fatalf("expected traversal path to be rejected")
	}
}
