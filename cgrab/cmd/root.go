package cmd

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"
)

func initRootHelp(rootCmd *cobra.Command) {
	rootCmd.SetHelpFunc(func(cmd *cobra.Command, args []string) {
		if cmd == rootCmd {
			fmt.Fprintln(cmd.OutOrStderr(), buildProductCard(detectCardWidth(cmd.OutOrStderr())))
			fmt.Fprintln(cmd.OutOrStderr())
		}
		cmd.Print(cmd.UsageString())
	})
}

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
		Use:           "cgrab",
		Aliases:       []string{"context-grabber"},
		Short:         "Context Grabber CLI",
		Example:       "  cgrab list tabs --browser safari\n  cgrab capture --focused\n  cgrab config show\n  cgrab docs",
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
		"write output to file",
	)
	rootCmd.PersistentFlags().BoolVar(
		&opts.clipboard,
		"clipboard",
		false,
		"copy output to clipboard",
	)
	rootCmd.PersistentFlags().StringVar(
		&opts.format,
		"format",
		formatMarkdown,
		"output format: json or markdown",
	)

	rootCmd.AddCommand(newListCommand(opts))
	rootCmd.AddCommand(newCaptureCommand(opts))
	rootCmd.AddCommand(newDoctorCommand(opts))
	rootCmd.AddCommand(newConfigCommand())
	rootCmd.AddCommand(newDocsCommand())
	rootCmd.CompletionOptions.DisableDefaultCmd = true
	applyCommandStyle(rootCmd)
	initRootHelp(rootCmd)

	return rootCmd
}

func Execute() error {
	return newRootCommand().Execute()
}
