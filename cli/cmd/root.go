package cmd

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"
)

const (
	formatJSON     = "json"
	formatMarkdown = "markdown"
)

// Version is injected at build-time via -ldflags.
var Version = "dev"

type globalOptions struct {
	outputFile string
	clipboard  bool
	format     string
}

func defaultGlobalOptions() *globalOptions {
	return &globalOptions{
		format: formatMarkdown,
	}
}

func newRootCommand() *cobra.Command {
	opts := defaultGlobalOptions()

	rootCmd := &cobra.Command{
		Use:           "context-grabber",
		Short:         "Context Grabber companion CLI",
		SilenceUsage:  true,
		SilenceErrors: true,
		PersistentPreRunE: func(_ *cobra.Command, _ []string) error {
			switch opts.format {
			case formatJSON, formatMarkdown:
				return nil
			default:
				return fmt.Errorf("unsupported --format value %q (expected json or markdown)", opts.format)
			}
		},
	}

	rootCmd.SetOut(os.Stdout)
	rootCmd.SetErr(os.Stderr)
	rootCmd.Version = Version

	rootCmd.PersistentFlags().StringVar(
		&opts.outputFile,
		"file",
		"",
		"write output to file instead of stdout",
	)
	rootCmd.PersistentFlags().BoolVar(
		&opts.clipboard,
		"clipboard",
		false,
		"copy command output to clipboard",
	)
	rootCmd.PersistentFlags().StringVar(
		&opts.format,
		"format",
		formatMarkdown,
		"output format: json or markdown",
	)

	rootCmd.AddCommand(newListCommand(opts))
	rootCmd.AddCommand(newDoctorCommand(opts))

	return rootCmd
}

func Execute() error {
	return newRootCommand().Execute()
}
