package osascript

import (
	"context"
	"fmt"
	"sort"
	"strconv"
	"strings"
)

type TabEntry struct {
	Browser     string `json:"browser"`
	WindowIndex int    `json:"windowIndex"`
	TabIndex    int    `json:"tabIndex"`
	IsActive    bool   `json:"isActive"`
	Title       string `json:"title"`
	URL         string `json:"url"`
}

func ListTabs(ctx context.Context, browserFilter string) ([]TabEntry, []string, error) {
	targets, err := resolveTabTargets(browserFilter)
	if err != nil {
		return nil, nil, err
	}

	var allEntries []TabEntry
	var warnings []string
	successCount := 0

	for _, browser := range targets {
		entries, listErr := listTabsForBrowser(ctx, browser)
		if listErr != nil {
			warnings = append(warnings, fmt.Sprintf("%s tabs unavailable: %v", browser, listErr))
			continue
		}
		successCount++
		allEntries = append(allEntries, entries...)
	}

	if successCount == 0 {
		return nil, warnings, fmt.Errorf("unable to enumerate tabs from requested browsers")
	}

	sortTabs(allEntries)
	return allEntries, warnings, nil
}

func resolveTabTargets(browserFilter string) ([]string, error) {
	normalized := strings.ToLower(strings.TrimSpace(browserFilter))
	switch normalized {
	case "":
		return []string{"safari", "chrome"}, nil
	case "safari", "chrome":
		return []string{normalized}, nil
	default:
		return nil, fmt.Errorf("unsupported --browser value %q (expected safari or chrome)", browserFilter)
	}
}

func listTabsForBrowser(ctx context.Context, browser string) ([]TabEntry, error) {
	script := safariTabsScript
	if browser == "chrome" {
		script = chromeTabsScript
	}

	output, err := runAppleScript(ctx, script)
	if err != nil {
		return nil, err
	}
	if strings.TrimSpace(output) == "" {
		return []TabEntry{}, nil
	}

	entries, err := parseTabEntries(browser, output)
	if err != nil {
		return nil, err
	}
	return entries, nil
}

func parseTabEntries(browser string, output string) ([]TabEntry, error) {
	records := strings.Split(output, recordSeparator)
	entries := make([]TabEntry, 0, len(records))

	for _, record := range records {
		record = strings.TrimSpace(record)
		if record == "" {
			continue
		}
		fields := strings.Split(record, fieldSeparator)
		if len(fields) != 5 {
			return nil, fmt.Errorf("invalid tab record field count %d", len(fields))
		}

		windowIndex, err := strconv.Atoi(strings.TrimSpace(fields[0]))
		if err != nil {
			return nil, fmt.Errorf("invalid window index %q: %w", fields[0], err)
		}
		tabIndex, err := strconv.Atoi(strings.TrimSpace(fields[1]))
		if err != nil {
			return nil, fmt.Errorf("invalid tab index %q: %w", fields[1], err)
		}

		entries = append(entries, TabEntry{
			Browser:     browser,
			WindowIndex: windowIndex,
			TabIndex:    tabIndex,
			IsActive:    parseAppleScriptBool(fields[2]),
			Title:       strings.TrimSpace(fields[3]),
			URL:         strings.TrimSpace(fields[4]),
		})
	}

	return entries, nil
}

func sortTabs(entries []TabEntry) {
	browserRank := map[string]int{
		"safari": 0,
		"chrome": 1,
	}

	sort.SliceStable(entries, func(i, j int) bool {
		leftRank := browserRank[entries[i].Browser]
		rightRank := browserRank[entries[j].Browser]
		if leftRank != rightRank {
			return leftRank < rightRank
		}
		if entries[i].WindowIndex != entries[j].WindowIndex {
			return entries[i].WindowIndex < entries[j].WindowIndex
		}
		return entries[i].TabIndex < entries[j].TabIndex
	})
}

func parseAppleScriptBool(value string) bool {
	normalized := strings.ToLower(strings.TrimSpace(value))
	return normalized == "true" || normalized == "yes" || normalized == "1"
}

const safariTabsScript = `
set fieldSep to ASCII character 30
set rowSep to ASCII character 31
set resultRows to {}

tell application "System Events"
	if not (exists process "Safari") then
		return ""
	end if
end tell

tell application "Safari"
	set windowCount to count of windows
	repeat with windowIndex from 1 to windowCount
		set tabCount to count of tabs of window windowIndex
		set activeIndex to index of current tab of window windowIndex
		repeat with tabIndex from 1 to tabCount
			set tabRef to tab tabIndex of window windowIndex
			set tabTitle to ""
			set tabURL to ""
			try
				set tabTitle to name of tabRef as text
			end try
			try
				set tabURL to URL of tabRef as text
			end try
			set activeText to ((tabIndex is activeIndex) as text)
			set end of resultRows to (windowIndex as text) & fieldSep & (tabIndex as text) & fieldSep & activeText & fieldSep & tabTitle & fieldSep & tabURL
		end repeat
	end repeat
end tell

return my joinRows(resultRows, rowSep)

on joinRows(values, separator)
	if (count of values) is 0 then
		return ""
	end if
	set AppleScript's text item delimiters to separator
	set joined to values as text
	set AppleScript's text item delimiters to ""
	return joined
end joinRows
`

const chromeTabsScript = `
set fieldSep to ASCII character 30
set rowSep to ASCII character 31
set resultRows to {}

tell application "System Events"
	if not (exists process "Google Chrome") then
		return ""
	end if
end tell

tell application "Google Chrome"
	set windowCount to count of windows
	repeat with windowIndex from 1 to windowCount
		set tabCount to count of tabs of window windowIndex
		set activeIndex to active tab index of window windowIndex
		repeat with tabIndex from 1 to tabCount
			set tabRef to tab tabIndex of window windowIndex
			set tabTitle to ""
			set tabURL to ""
			try
				set tabTitle to title of tabRef as text
			end try
			try
				set tabURL to URL of tabRef as text
			end try
			set activeText to ((tabIndex is activeIndex) as text)
			set end of resultRows to (windowIndex as text) & fieldSep & (tabIndex as text) & fieldSep & activeText & fieldSep & tabTitle & fieldSep & tabURL
		end repeat
	end repeat
end tell

return my joinRows(resultRows, rowSep)

on joinRows(values, separator)
	if (count of values) is 0 then
		return ""
	end if
	set AppleScript's text item delimiters to separator
	set joined to values as text
	set AppleScript's text item delimiters to ""
	return joined
end joinRows
`
