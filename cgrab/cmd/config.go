package cmd

import (
	"fmt"
	"path/filepath"
	"strings"

	"github.com/anthonylu23/context_grabber/cgrab/internal/config"
	"github.com/spf13/cobra"
)

func newConfigCommand() *cobra.Command {
	configCmd := &cobra.Command{
		Use:   "config",
		Short: "Manage cgrab settings",
	}

	configCmd.AddCommand(newConfigShowCommand())
	configCmd.AddCommand(newConfigSetOutputDirCommand())
	configCmd.AddCommand(newConfigResetOutputDirCommand())
	return configCmd
}

func newConfigShowCommand() *cobra.Command {
	return &cobra.Command{
		Use:   "show",
		Short: "Show current config",
		RunE: func(cmd *cobra.Command, _ []string) error {
			settings, err := config.LoadSettings()
			if err != nil {
				return err
			}
			baseDir, captureDir, err := config.EnsureBaseLayout(settings)
			if err != nil {
				return err
			}
			configPath := config.ResolveConfigFilePath(baseDir)

			fmt.Fprintf(cmd.OutOrStdout(), "Context Grabber CLI Config\n")
			fmt.Fprintf(cmd.OutOrStdout(), "-------------------------\n")
			fmt.Fprintf(cmd.OutOrStdout(), "base_dir: %s\n", baseDir)
			fmt.Fprintf(cmd.OutOrStdout(), "config_file: %s\n", configPath)
			fmt.Fprintf(cmd.OutOrStdout(), "capture_output_subdir: %s\n", settings.CaptureOutputSubdir)
			fmt.Fprintf(cmd.OutOrStdout(), "capture_output_dir: %s\n", captureDir)
			return nil
		},
	}
}

func newConfigSetOutputDirCommand() *cobra.Command {
	return &cobra.Command{
		Use:     "set-output-dir <subdir>",
		Aliases: []string{"set-path"},
		Short:   "Set capture output subdirectory",
		Example: "  cgrab config set-output-dir captures\n  cgrab config set-output-dir projects/client-a",
		Args:    cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			subdir := strings.TrimSpace(args[0])
			if subdir == "" {
				return fmt.Errorf("output subdirectory cannot be empty")
			}

			settings, err := config.LoadSettings()
			if err != nil {
				return err
			}
			settings.CaptureOutputSubdir = filepath.Clean(subdir)
			if err := config.SaveSettings(settings); err != nil {
				return err
			}

			_, captureDir, err := config.EnsureBaseLayout(settings)
			if err != nil {
				return err
			}
			fmt.Fprintf(cmd.OutOrStdout(), "Updated capture output directory: %s\n", captureDir)
			return nil
		},
	}
}

func newConfigResetOutputDirCommand() *cobra.Command {
	return &cobra.Command{
		Use:   "reset-output-dir",
		Short: "Reset capture output subdirectory to default",
		RunE: func(cmd *cobra.Command, _ []string) error {
			settings, err := config.LoadSettings()
			if err != nil {
				return err
			}
			settings.CaptureOutputSubdir = config.DefaultSettings().CaptureOutputSubdir
			if err := config.SaveSettings(settings); err != nil {
				return err
			}
			_, captureDir, err := config.EnsureBaseLayout(settings)
			if err != nil {
				return err
			}
			fmt.Fprintf(cmd.OutOrStdout(), "Reset capture output directory to: %s\n", captureDir)
			return nil
		},
	}
}
