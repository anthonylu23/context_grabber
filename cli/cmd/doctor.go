package cmd

import (
	"encoding/json"
	"fmt"
	"strings"

	"github.com/anthonylu23/context_grabber/cli/internal/bridge"
	"github.com/anthonylu23/context_grabber/cli/internal/output"
	"github.com/spf13/cobra"
)

func newDoctorCommand(global *globalOptions) *cobra.Command {
	doctorCmd := &cobra.Command{
		Use:   "doctor",
		Short: "Check companion CLI capabilities and bridge health",
		RunE: func(cmd *cobra.Command, _ []string) error {
			report, err := bridge.RunDoctor(cmd.Context())
			if err != nil {
				return err
			}

			var rendered []byte
			switch global.format {
			case formatJSON:
				rendered, err = json.MarshalIndent(report, "", "  ")
			case formatMarkdown:
				rendered = []byte(formatDoctorMarkdown(report))
			default:
				err = fmt.Errorf("unsupported format: %s", global.format)
			}
			if err != nil {
				return err
			}

			if err := output.Write(cmd.Context(), rendered, global.outputFile, global.clipboard); err != nil {
				return err
			}

			if report.OverallStatus != "ready" {
				return fmt.Errorf("doctor status is %s", report.OverallStatus)
			}
			return nil
		},
	}
	return doctorCmd
}

func formatDoctorMarkdown(report bridge.DoctorReport) string {
	lines := []string{
		"# Context Grabber Doctor",
		fmt.Sprintf("- overall_status: %s", report.OverallStatus),
		fmt.Sprintf("- repo_root: %s", report.RepoRoot),
		fmt.Sprintf("- osascript_available: %t", report.OsaScriptAvailable),
		fmt.Sprintf("- bun_available: %t", report.BunAvailable),
		fmt.Sprintf("- host_binary_available: %t", report.HostBinaryAvailable),
	}
	if report.HostBinaryPath != "" {
		lines = append(lines, fmt.Sprintf("- host_binary_path: %s", report.HostBinaryPath))
	}
	lines = append(lines, "", "## Bridge Status")
	for _, bridgeStatus := range report.Bridges {
		line := fmt.Sprintf("- %s: %s", bridgeStatus.Target, bridgeStatus.Status)
		if bridgeStatus.Detail != "" {
			line += " (" + bridgeStatus.Detail + ")"
		}
		lines = append(lines, line)
	}
	if len(report.Warnings) > 0 {
		lines = append(lines, "", "## Warnings")
		for _, warning := range report.Warnings {
			lines = append(lines, "- "+warning)
		}
	}
	return strings.Join(lines, "\n") + "\n"
}
