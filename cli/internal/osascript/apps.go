package osascript

import (
	"context"
	"fmt"
	"sort"
	"strconv"
	"strings"
)

type AppEntry struct {
	AppName          string `json:"appName"`
	BundleIdentifier string `json:"bundleIdentifier"`
	WindowCount      int    `json:"windowCount"`
}

func ListApps(ctx context.Context) ([]AppEntry, error) {
	output, err := runAppleScript(ctx, appsScript)
	if err != nil {
		return nil, err
	}
	if strings.TrimSpace(output) == "" {
		return []AppEntry{}, nil
	}

	entries, err := parseAppEntries(output)
	if err != nil {
		return nil, err
	}
	sortApps(entries)
	return entries, nil
}

func parseAppEntries(output string) ([]AppEntry, error) {
	records := strings.Split(output, recordSeparator)
	entries := make([]AppEntry, 0, len(records))

	for _, record := range records {
		record = strings.TrimSpace(record)
		if record == "" {
			continue
		}
		fields := strings.Split(record, fieldSeparator)
		if len(fields) != 3 {
			return nil, fmt.Errorf("invalid app record field count %d", len(fields))
		}

		windowCount, err := strconv.Atoi(strings.TrimSpace(fields[2]))
		if err != nil {
			return nil, fmt.Errorf("invalid window count %q: %w", fields[2], err)
		}
		entries = append(entries, AppEntry{
			AppName:          strings.TrimSpace(fields[0]),
			BundleIdentifier: strings.TrimSpace(fields[1]),
			WindowCount:      windowCount,
		})
	}
	return entries, nil
}

func sortApps(entries []AppEntry) {
	sort.SliceStable(entries, func(i, j int) bool {
		if entries[i].AppName != entries[j].AppName {
			return entries[i].AppName < entries[j].AppName
		}
		return entries[i].BundleIdentifier < entries[j].BundleIdentifier
	})
}

const appsScript = `
set fieldSep to ASCII character 30
set rowSep to ASCII character 31
set resultRows to {}

tell application "System Events"
	set processList to every application process whose background only is false
	repeat with processRef in processList
		set windowCount to 0
		try
			set windowCount to count of windows of processRef
		on error
			set windowCount to 0
		end try
		if windowCount is greater than 0 then
			set appName to name of processRef as text
			set bundleID to ""
			try
				set bundleID to bundle identifier of processRef as text
			end try
			set end of resultRows to appName & fieldSep & bundleID & fieldSep & (windowCount as text)
		end if
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
