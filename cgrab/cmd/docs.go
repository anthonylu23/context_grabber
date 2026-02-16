package cmd

import (
	"context"
	"fmt"
	"os/exec"

	"github.com/spf13/cobra"
)

const repoDocsURL = "https://github.com/anthonylu23/context_grabber"

var openURLFunc = openURL

func newDocsCommand() *cobra.Command {
	return &cobra.Command{
		Use:   "docs",
		Short: "Open docs in browser",
		RunE: func(cmd *cobra.Command, _ []string) error {
			if err := openURLFunc(cmd.Context(), repoDocsURL); err != nil {
				fmt.Fprintf(cmd.ErrOrStderr(), "warning: could not open browser (%v)\n", err)
				fmt.Fprintf(cmd.OutOrStdout(), "%s\n", repoDocsURL)
				return nil
			}

			fmt.Fprintf(cmd.OutOrStdout(), "Opened docs: %s\n", repoDocsURL)
			return nil
		},
	}
}

func openURL(ctx context.Context, url string) error {
	openers := [][]string{
		{"open", url},
		{"xdg-open", url},
	}
	var lastErr error
	for _, opener := range openers {
		cmd := exec.CommandContext(ctx, opener[0], opener[1:]...)
		if err := cmd.Run(); err == nil {
			return nil
		} else {
			lastErr = err
		}
	}
	return lastErr
}
