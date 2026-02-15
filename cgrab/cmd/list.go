package cmd

import (
	"encoding/json"
	"fmt"
	"io"
	"sort"
	"strings"

	"github.com/anthonylu23/context_grabber/cgrab/internal/osascript"
	"github.com/anthonylu23/context_grabber/cgrab/internal/output"
	"github.com/spf13/cobra"
)

func newListCommand(global *globalOptions) *cobra.Command {
	var includeTabs bool
	var includeApps bool
	var browser string

	listCmd := &cobra.Command{
		Use:   "list",
		Short: "List tabs and apps",
		Example: "  cgrab list\n" +
			"  cgrab list --tabs --browser chrome --format json\n" +
			"  cgrab list --apps\n" +
			"  cgrab list tabs",
		RunE: func(cmd *cobra.Command, _ []string) error {
			selection := resolveListSelection(includeTabs, includeApps)
			result := combinedListResult{
				Tabs: []osascript.TabEntry{},
				Apps: []osascript.AppEntry{},
			}

			successCount := 0
			var failures []string
			if selection.tabs {
				tabs, warnings, err := listTabsFunc(cmd.Context(), browser)
				writeWarnings(cmd.ErrOrStderr(), warnings)
				if err != nil {
					failures = append(failures, fmt.Sprintf("tabs failed: %v", err))
				} else {
					result.Tabs = tabs
					successCount++
				}
			}
			if selection.apps {
				apps, err := listAppsFunc(cmd.Context())
				if err != nil {
					failures = append(failures, fmt.Sprintf("apps failed: %v", err))
				} else {
					result.Apps = apps
					successCount++
				}
			}

			if len(failures) > 0 && successCount == 0 {
				return fmt.Errorf("%s", strings.Join(failures, "; "))
			}
			if len(failures) > 0 {
				writeWarnings(cmd.ErrOrStderr(), failures)
			}

			rendered, err := renderCombinedList(global.format, selection, result)
			if err != nil {
				return err
			}
			return output.Write(cmd.Context(), rendered, global.outputFile, global.clipboard)
		},
	}

	listCmd.AddCommand(newListTabsCommand(global))
	listCmd.AddCommand(newListAppsCommand(global))
	listCmd.Flags().BoolVar(&includeTabs, "tabs", false, "include browser tabs")
	listCmd.Flags().BoolVar(&includeApps, "apps", false, "include running desktop apps")
	listCmd.Flags().StringVar(&browser, "browser", "", "browser filter for tabs: safari or chrome")
	return listCmd
}

type listSelection struct {
	tabs bool
	apps bool
}

func resolveListSelection(includeTabs bool, includeApps bool) listSelection {
	if !includeTabs && !includeApps {
		return listSelection{tabs: true, apps: true}
	}
	return listSelection{tabs: includeTabs, apps: includeApps}
}

type combinedListResult struct {
	Tabs []osascript.TabEntry `json:"tabs"`
	Apps []osascript.AppEntry `json:"apps"`
}

func renderCombinedList(format string, selection listSelection, result combinedListResult) ([]byte, error) {
	if selection.tabs && !selection.apps {
		return renderTabs(format, result.Tabs)
	}
	if selection.apps && !selection.tabs {
		return renderApps(format, result.Apps)
	}

	switch format {
	case formatJSON:
		return json.MarshalIndent(result, "", "  ")
	case formatMarkdown:
		tabsMarkdown, err := renderTabs(formatMarkdown, result.Tabs)
		if err != nil {
			return nil, err
		}
		appsMarkdown, err := renderApps(formatMarkdown, result.Apps)
		if err != nil {
			return nil, err
		}
		combined := strings.TrimSpace(string(tabsMarkdown)) + "\n\n" + strings.TrimSpace(string(appsMarkdown)) + "\n"
		return []byte(combined), nil
	default:
		return nil, fmt.Errorf("unsupported format: %s", format)
	}
}

func newListTabsCommand(global *globalOptions) *cobra.Command {
	var browser string
	tabsCmd := &cobra.Command{
		Use:   "tabs",
		Short: "Show open browser tabs",
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
	tabsCmd.Flags().StringVar(&browser, "browser", "", "browser: safari or chrome")
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
		Short: "Show running desktop apps",
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
