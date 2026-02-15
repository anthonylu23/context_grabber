package osascript

import (
	"context"
	"fmt"
	"strconv"
	"strings"
)

func ActivateTab(ctx context.Context, browser string, windowIndex int, tabIndex int) error {
	switch strings.ToLower(strings.TrimSpace(browser)) {
	case "safari":
		return activateSafariTab(ctx, windowIndex, tabIndex)
	case "chrome":
		return activateChromeTab(ctx, windowIndex, tabIndex)
	default:
		return fmt.Errorf("unsupported browser %q (expected safari or chrome)", browser)
	}
}

func ActivateAppByName(ctx context.Context, appName string) error {
	name := strings.TrimSpace(appName)
	if name == "" {
		return fmt.Errorf("app name is required")
	}

	if _, err := runAppleScriptWithArgs(ctx, activateAppByNameScript, name); err != nil {
		return err
	}
	return nil
}

func ActivateAppByBundleID(ctx context.Context, bundleIdentifier string) error {
	bundleID := strings.TrimSpace(bundleIdentifier)
	if bundleID == "" {
		return fmt.Errorf("bundle identifier is required")
	}

	if _, err := runAppleScriptWithArgs(ctx, activateAppByBundleIDScript, bundleID); err != nil {
		return err
	}
	return nil
}

func activateSafariTab(ctx context.Context, windowIndex int, tabIndex int) error {
	if windowIndex <= 0 || tabIndex <= 0 {
		return fmt.Errorf("window and tab index must be positive")
	}
	_, err := runAppleScriptWithArgs(
		ctx,
		activateSafariTabScript,
		strconv.Itoa(windowIndex),
		strconv.Itoa(tabIndex),
	)
	return err
}

func activateChromeTab(ctx context.Context, windowIndex int, tabIndex int) error {
	if windowIndex <= 0 || tabIndex <= 0 {
		return fmt.Errorf("window and tab index must be positive")
	}
	_, err := runAppleScriptWithArgs(
		ctx,
		activateChromeTabScript,
		strconv.Itoa(windowIndex),
		strconv.Itoa(tabIndex),
	)
	return err
}

const activateSafariTabScript = `
on run argv
	if (count of argv) is not 2 then
		error "Expected arguments: <windowIndex> <tabIndex>"
	end if
	set windowIndex to item 1 of argv as integer
	set tabIndex to item 2 of argv as integer

	tell application "System Events"
		if not (exists process "Safari") then
			error "Safari is not running."
		end if
	end tell

	tell application "Safari"
		if windowIndex > (count of windows) then
			error "Safari window index out of range."
		end if
		tell window windowIndex
			if tabIndex > (count of tabs) then
				error "Safari tab index out of range."
			end if
			set current tab to tab tabIndex
			set index to 1
		end tell
		activate
	end tell
end run
`

const activateChromeTabScript = `
on run argv
	if (count of argv) is not 2 then
		error "Expected arguments: <windowIndex> <tabIndex>"
	end if
	set windowIndex to item 1 of argv as integer
	set tabIndex to item 2 of argv as integer

	tell application "System Events"
		if not (exists process "Google Chrome") then
			error "Google Chrome is not running."
		end if
	end tell

	tell application "Google Chrome"
		if windowIndex > (count of windows) then
			error "Chrome window index out of range."
		end if
		tell window windowIndex
			if tabIndex > (count of tabs) then
				error "Chrome tab index out of range."
			end if
			set active tab index to tabIndex
		end tell
		activate
	end tell
end run
`

const activateAppByNameScript = `
on run argv
	if (count of argv) is not 1 then
		error "Expected argument: <appName>"
	end if

	set appName to item 1 of argv as text
	tell application appName to activate
end run
`

const activateAppByBundleIDScript = `
on run argv
	if (count of argv) is not 1 then
		error "Expected argument: <bundleIdentifier>"
	end if

	set targetBundleID to item 1 of argv as text
	tell application "System Events"
		set matchingProcesses to application processes whose bundle identifier is targetBundleID
		if (count of matchingProcesses) is 0 then
			error "No running app found for bundle id " & targetBundleID
		end if
		set appName to name of item 1 of matchingProcesses as text
	end tell
	tell application appName to activate
end run
`
