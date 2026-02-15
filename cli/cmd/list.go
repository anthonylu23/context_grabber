package cmd

import (
	"encoding/json"
	"fmt"
	"io"
	"sort"
	"strings"

	"github.com/anthonylu23/context_grabber/cli/internal/osascript"
	"github.com/anthonylu23/context_grabber/cli/internal/output"
	"github.com/spf13/cobra"
)

func newListCommand(global *globalOptions) *cobra.Command {
	listCmd := &cobra.Command{
		Use:   "list",
		Short: "Enumerate tabs and desktop apps",
	}

	listCmd.AddCommand(newListTabsCommand(global))
	listCmd.AddCommand(newListAppsCommand(global))
	return listCmd
}

func newListTabsCommand(global *globalOptions) *cobra.Command {
	var browser string
	tabsCmd := &cobra.Command{
		Use:   "tabs",
		Short: "List open browser tabs (Safari and Chrome)",
		RunE: func(cmd *cobra.Command, _ []string) error {
			tabs, warnings, err := osascript.ListTabs(cmd.Context(), browser)
			writeWarnings(cmd.ErrOrStderr(), warnings)
			if err != nil {
				return err
			}

			rendered, err := renderTabs(global.format, tabs)
			if err != nil {
				return err
			}
			return output.Write(cmd.Context(), rendered, global.outputFile, global.clipboard)
		},
	}
	tabsCmd.Flags().StringVar(&browser, "browser", "", "restrict to browser: safari or chrome")
	return tabsCmd
}

func writeWarnings(stderr io.Writer, warnings []string) {
	for _, warning := range warnings {
		fmt.Fprintf(stderr, "warning: %s\n", warning)
	}
}

func newListAppsCommand(global *globalOptions) *cobra.Command {
	appsCmd := &cobra.Command{
		Use:   "apps",
		Short: "List running desktop apps that have open windows",
		RunE: func(cmd *cobra.Command, _ []string) error {
			apps, err := osascript.ListApps(cmd.Context())
			if err != nil {
				return err
			}
			rendered, err := renderApps(global.format, apps)
			if err != nil {
				return err
			}
			return output.Write(cmd.Context(), rendered, global.outputFile, global.clipboard)
		},
	}
	return appsCmd
}

func renderTabs(format string, tabs []osascript.TabEntry) ([]byte, error) {
	switch format {
	case formatJSON:
		return json.MarshalIndent(tabs, "", "  ")
	case formatMarkdown:
		if len(tabs) == 0 {
			return []byte("No tabs found.\n"), nil
		}
		var lines []string
		lines = append(lines, "# Open Tabs")
		sort.SliceStable(tabs, func(i, j int) bool {
			if tabs[i].Browser != tabs[j].Browser {
				return tabs[i].Browser < tabs[j].Browser
			}
			if tabs[i].WindowIndex != tabs[j].WindowIndex {
				return tabs[i].WindowIndex < tabs[j].WindowIndex
			}
			return tabs[i].TabIndex < tabs[j].TabIndex
		})
		for _, tab := range tabs {
			activeLabel := ""
			if tab.IsActive {
				activeLabel = " (active)"
			}
			lines = append(
				lines,
				fmt.Sprintf(
					"- %s w%d:t%d%s - %s - %s",
					tab.Browser,
					tab.WindowIndex,
					tab.TabIndex,
					activeLabel,
					tab.Title,
					tab.URL,
				),
			)
		}
		return []byte(strings.Join(lines, "\n") + "\n"), nil
	default:
		return nil, fmt.Errorf("unsupported format: %s", format)
	}
}

func renderApps(format string, apps []osascript.AppEntry) ([]byte, error) {
	switch format {
	case formatJSON:
		return json.MarshalIndent(apps, "", "  ")
	case formatMarkdown:
		if len(apps) == 0 {
			return []byte("No desktop apps with windows found.\n"), nil
		}
		var lines []string
		lines = append(lines, "# Running Apps")
		sort.SliceStable(apps, func(i, j int) bool {
			if apps[i].AppName != apps[j].AppName {
				return apps[i].AppName < apps[j].AppName
			}
			return apps[i].BundleIdentifier < apps[j].BundleIdentifier
		})
		for _, app := range apps {
			lines = append(
				lines,
				fmt.Sprintf("- %s (%s) - windows: %d", app.AppName, app.BundleIdentifier, app.WindowCount),
			)
		}
		return []byte(strings.Join(lines, "\n") + "\n"), nil
	default:
		return nil, fmt.Errorf("unsupported format: %s", format)
	}
}
