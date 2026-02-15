package config

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

const (
	cliHomeOverrideEnvVar = "CONTEXT_GRABBER_CLI_HOME"
	defaultBaseFolderName = "contextgrabber"
	defaultCaptureSubdir  = "captures"
	configFileName        = "config.json"
)

type Settings struct {
	CaptureOutputSubdir string `json:"captureOutputSubdir"`
}

func DefaultSettings() Settings {
	return Settings{
		CaptureOutputSubdir: defaultCaptureSubdir,
	}
}

func ResolveBaseDir() (string, error) {
	if override := strings.TrimSpace(os.Getenv(cliHomeOverrideEnvVar)); override != "" {
		if !filepath.IsAbs(override) {
			return "", fmt.Errorf("%s must be an absolute path", cliHomeOverrideEnvVar)
		}
		return filepath.Clean(override), nil
	}

	homeDir, err := os.UserHomeDir()
	if err != nil {
		return "", fmt.Errorf("resolve user home dir: %w", err)
	}

	return filepath.Join(homeDir, defaultBaseFolderName), nil
}

func ResolveConfigFilePath(baseDir string) string {
	return filepath.Join(baseDir, configFileName)
}

func LoadSettings() (Settings, error) {
	baseDir, err := ResolveBaseDir()
	if err != nil {
		return Settings{}, err
	}
	configFilePath := ResolveConfigFilePath(baseDir)
	raw, err := os.ReadFile(configFilePath)
	if err != nil {
		if os.IsNotExist(err) {
			return DefaultSettings(), nil
		}
		return Settings{}, fmt.Errorf("read config file: %w", err)
	}

	settings := DefaultSettings()
	if err := json.Unmarshal(raw, &settings); err != nil {
		return Settings{}, fmt.Errorf("decode config file: %w", err)
	}
	if settings.CaptureOutputSubdir, err = normalizeCaptureSubdir(settings.CaptureOutputSubdir); err != nil {
		return Settings{}, err
	}

	return settings, nil
}

func SaveSettings(settings Settings) error {
	baseDir, err := ResolveBaseDir()
	if err != nil {
		return err
	}
	cleanSubdir, err := normalizeCaptureSubdir(settings.CaptureOutputSubdir)
	if err != nil {
		return err
	}
	settings.CaptureOutputSubdir = cleanSubdir

	if err := os.MkdirAll(baseDir, 0o755); err != nil {
		return fmt.Errorf("create base config directory: %w", err)
	}
	configFilePath := ResolveConfigFilePath(baseDir)
	payload, err := json.MarshalIndent(settings, "", "  ")
	if err != nil {
		return fmt.Errorf("encode config: %w", err)
	}

	if err := os.WriteFile(configFilePath, append(payload, '\n'), 0o644); err != nil {
		return fmt.Errorf("write config file: %w", err)
	}
	return nil
}

func ResolveCaptureOutputDir(settings Settings) (string, error) {
	baseDir, err := ResolveBaseDir()
	if err != nil {
		return "", err
	}
	cleanSubdir, err := normalizeCaptureSubdir(settings.CaptureOutputSubdir)
	if err != nil {
		return "", err
	}
	return filepath.Join(baseDir, cleanSubdir), nil
}

func EnsureBaseLayout(settings Settings) (baseDir string, captureDir string, err error) {
	baseDir, err = ResolveBaseDir()
	if err != nil {
		return "", "", err
	}
	captureDir, err = ResolveCaptureOutputDir(settings)
	if err != nil {
		return "", "", err
	}

	if err := os.MkdirAll(baseDir, 0o755); err != nil {
		return "", "", fmt.Errorf("create base directory: %w", err)
	}
	if err := os.MkdirAll(captureDir, 0o755); err != nil {
		return "", "", fmt.Errorf("create capture output directory: %w", err)
	}

	return baseDir, captureDir, nil
}

func normalizeCaptureSubdir(raw string) (string, error) {
	value := strings.TrimSpace(raw)
	if value == "" {
		return defaultCaptureSubdir, nil
	}
	if filepath.IsAbs(value) {
		return "", fmt.Errorf("capture output path must be relative to %q", defaultBaseFolderName)
	}
	cleaned := filepath.Clean(value)
	if cleaned == "." || cleaned == "" {
		return defaultCaptureSubdir, nil
	}
	parentPrefix := ".." + string(filepath.Separator)
	if cleaned == ".." || strings.HasPrefix(cleaned, parentPrefix) {
		return "", fmt.Errorf("capture output path cannot escape %q", defaultBaseFolderName)
	}
	return cleaned, nil
}
