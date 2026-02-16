package cmd

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/anthonylu23/context_grabber/cgrab/internal/bridge"
	"github.com/anthonylu23/context_grabber/cgrab/internal/config"
	"github.com/anthonylu23/context_grabber/cgrab/internal/osascript"
	"github.com/anthonylu23/context_grabber/cgrab/internal/output"
	"github.com/spf13/cobra"
)

var (
	listTabsFunc             = osascript.ListTabs
	listAppsFunc             = osascript.ListApps
	activateTabFunc          = osascript.ActivateTab
	activateAppByNameFunc    = osascript.ActivateAppByName
	activateAppByBundleFunc  = osascript.ActivateAppByBundleID
	captureBrowserFunc       = bridge.CaptureBrowser
	captureDesktopFunc       = bridge.CaptureDesktop
	ensureHostAppRunningFunc = bridge.EnsureHostAppRunning
	nowFunc                  = time.Now
)

func newCaptureCommand(global *globalOptions) *cobra.Command {
	var focused bool
	var tabReference string
	var urlMatch string
	var titleMatch string
	var appName string
	var nameMatch string
	var bundleID string
	var browser string
	var method string
	var timeoutMs int

	captureCmd := &cobra.Command{
		Use:   "capture",
		Short: "Capture browser or desktop context",
		Example: "  cgrab capture --focused\n" +
			"  cgrab capture --tab w1:t2 --browser safari\n" +
			"  cgrab capture --app Finder --method auto\n" +
			"  cgrab capture --app --name-match xcode --format json",
		RunE: func(cmd *cobra.Command, args []string) error {
			if len(args) > 0 {
				return fmt.Errorf("capture does not accept positional args: %s", strings.Join(args, " "))
			}

			request := captureRequest{
				focused:      focused,
				tabReference: strings.TrimSpace(tabReference),
				urlMatch:     strings.TrimSpace(urlMatch),
				titleMatch:   strings.TrimSpace(titleMatch),
				appName:      strings.TrimSpace(appName),
				nameMatch:    strings.TrimSpace(nameMatch),
				bundleID:     strings.TrimSpace(bundleID),
				browser:      strings.TrimSpace(browser),
				method:       strings.ToLower(strings.TrimSpace(method)),
				timeoutMs:    timeoutMs,
				outputFormat: global.format,
			}

			mode, err := request.validate()
			if err != nil {
				return err
			}

			stderr := cmd.ErrOrStderr()
			var rendered []byte
			switch mode {
			case captureModeBrowser:
				rendered, err = runBrowserCapture(cmd.Context(), request, stderr)
			case captureModeDesktop:
				rendered, err = runDesktopCapture(cmd.Context(), request)
			default:
				err = fmt.Errorf("unsupported capture mode")
			}
			if err != nil {
				return err
			}

			outputFile := strings.TrimSpace(global.outputFile)
			autoSave := false
			if outputFile == "" {
				defaultOutputFile, pathErr := resolveDefaultCaptureOutputFilePath(request.outputFormat)
				if pathErr != nil {
					return pathErr
				}
				outputFile = defaultOutputFile
				autoSave = true
			}

			if err := output.Write(cmd.Context(), rendered, outputFile, global.clipboard); err != nil {
				return err
			}
			if autoSave {
				fmt.Fprintf(cmd.OutOrStdout(), "Saved capture to %s\n", outputFile)
			}
			return nil
		},
	}

	captureCmd.Flags().BoolVar(&focused, "focused", false, "focused browser tab")
	captureCmd.Flags().StringVar(&tabReference, "tab", "", "tab by window:tab index (e.g. 1:2 or w1:t2)")
	captureCmd.Flags().StringVar(&urlMatch, "url-match", "", "match tab by URL substring")
	captureCmd.Flags().StringVar(&titleMatch, "title-match", "", "match tab by title substring")
	captureCmd.Flags().StringVar(&appName, "app", "", "app by exact name")
	captureCmd.Flags().StringVar(&nameMatch, "name-match", "", "match app by name substring")
	captureCmd.Flags().StringVar(&bundleID, "bundle-id", "", "app by bundle identifier")
	captureCmd.Flags().StringVar(&browser, "browser", "", "browser: safari or chrome")
	captureCmd.Flags().StringVar(&method, "method", "auto", "method: auto|applescript|extension|ax|ocr")
	captureCmd.Flags().IntVar(&timeoutMs, "timeout-ms", 1200, "timeout in milliseconds")

	return captureCmd
}

type captureMode string

const (
	captureModeBrowser captureMode = "browser"
	captureModeDesktop captureMode = "desktop"
)

type captureRequest struct {
	focused      bool
	tabReference string
	urlMatch     string
	titleMatch   string
	appName      string
	nameMatch    string
	bundleID     string
	browser      string
	method       string
	timeoutMs    int
	outputFormat string
}

func (r captureRequest) validate() (captureMode, error) {
	if r.timeoutMs <= 0 {
		return "", fmt.Errorf("timeout must be positive")
	}
	if r.outputFormat != formatJSON && r.outputFormat != formatMarkdown {
		return "", fmt.Errorf("unsupported --format value %q", r.outputFormat)
	}

	browserSelectors := 0
	if r.focused {
		browserSelectors++
	}
	if r.tabReference != "" {
		browserSelectors++
	}
	if r.urlMatch != "" {
		browserSelectors++
	}
	if r.titleMatch != "" {
		browserSelectors++
	}

	desktopSelectors := 0
	if r.appName != "" {
		desktopSelectors++
	}
	if r.nameMatch != "" {
		desktopSelectors++
	}
	if r.bundleID != "" {
		desktopSelectors++
	}

	if browserSelectors == 0 && desktopSelectors == 0 {
		return "", fmt.Errorf("capture requires one target selector (e.g. --focused, --tab, --url-match, --app, --name-match, --bundle-id)")
	}
	if browserSelectors > 0 && desktopSelectors > 0 {
		return "", fmt.Errorf("capture selectors must be either browser-targeted or app-targeted, not both")
	}
	if browserSelectors > 1 {
		return "", fmt.Errorf("browser capture accepts only one selector: --focused, --tab, --url-match, or --title-match")
	}
	if desktopSelectors > 1 {
		return "", fmt.Errorf("desktop capture accepts only one selector: --app, --name-match, or --bundle-id")
	}

	if browserSelectors > 0 {
		if _, err := toBrowserCaptureSource(r.method); err != nil {
			return "", err
		}
		if _, err := parseOptionalBrowserTarget(r.browser); err != nil {
			return "", err
		}
		return captureModeBrowser, nil
	}

	if _, err := toDesktopCaptureMethod(r.method); err != nil {
		return "", err
	}
	return captureModeDesktop, nil
}

func runBrowserCapture(ctx context.Context, request captureRequest, stderr io.Writer) ([]byte, error) {
	if _, launchErr := ensureHostAppRunningFunc(ctx); launchErr != nil {
		fmt.Fprintf(
			stderr,
			"warning: unable to auto-launch ContextGrabber app before browser capture (%v)\n",
			launchErr,
		)
	}

	targetOverride, envErr := resolveBrowserTargetOverrideEnv()
	if envErr != nil {
		return nil, envErr
	}
	flagTarget, err := parseOptionalBrowserTarget(request.browser)
	if err != nil {
		return nil, err
	}
	if flagTarget != "" {
		targetOverride = flagTarget
	}

	source, err := toBrowserCaptureSource(request.method)
	if err != nil {
		return nil, err
	}

	if request.focused {
		targets := focusedTargetOrder(targetOverride)
		attempt, target, captureErr := captureBrowserWithFallback(
			ctx,
			targets,
			source,
			request.timeoutMs,
			bridge.BrowserCaptureMetadata{},
		)
		if captureErr != nil {
			return nil, captureErr
		}
		return encodeBrowserCaptureOutput(request.outputFormat, target, attempt)
	}

	selectedTab, err := resolveTargetTab(ctx, request, targetOverride, stderr)
	if err != nil {
		return nil, err
	}

	if err := activateTabFunc(
		ctx,
		selectedTab.Browser,
		selectedTab.WindowIndex,
		selectedTab.TabIndex,
	); err != nil {
		return nil, fmt.Errorf(
			"failed to activate %s tab w%d:t%d: %w",
			selectedTab.Browser,
			selectedTab.WindowIndex,
			selectedTab.TabIndex,
			err,
		)
	}

	target, err := parseOptionalBrowserTarget(selectedTab.Browser)
	if err != nil {
		return nil, err
	}
	attempt, _, captureErr := captureBrowserWithFallback(
		ctx,
		[]bridge.BrowserTarget{target},
		source,
		request.timeoutMs,
		bridge.BrowserCaptureMetadata{
			Title: selectedTab.Title,
			URL:   selectedTab.URL,
		},
	)
	if captureErr != nil {
		return nil, captureErr
	}
	return encodeBrowserCaptureOutput(request.outputFormat, target, attempt)
}

func runDesktopCapture(ctx context.Context, request captureRequest) ([]byte, error) {
	targetAppName := request.appName
	targetBundleID := request.bundleID

	if request.nameMatch != "" {
		apps, err := listAppsFunc(ctx)
		if err != nil {
			return nil, err
		}
		matched := findAppByNameMatch(apps, request.nameMatch)
		if matched == nil {
			return nil, fmt.Errorf("no running app matched --name-match %q", request.nameMatch)
		}
		targetAppName = matched.AppName
		targetBundleID = matched.BundleIdentifier
	}

	if targetBundleID != "" {
		if err := activateAppByBundleFunc(ctx, targetBundleID); err != nil {
			return nil, fmt.Errorf("failed to activate app %s: %w", targetBundleID, err)
		}
	} else if targetAppName != "" {
		if err := activateAppByNameFunc(ctx, targetAppName); err != nil {
			return nil, fmt.Errorf("failed to activate app %s: %w", targetAppName, err)
		}
	}

	method, err := toDesktopCaptureMethod(request.method)
	if err != nil {
		return nil, err
	}

	captureFormat := bridge.DesktopCaptureFormatMarkdown
	if request.outputFormat == formatJSON {
		captureFormat = bridge.DesktopCaptureFormatJSON
	}

	return captureDesktopFunc(ctx, bridge.DesktopCaptureRequest{
		AppName:          targetAppName,
		BundleIdentifier: targetBundleID,
		Method:           method,
		Format:           captureFormat,
	})
}

func captureBrowserWithFallback(
	ctx context.Context,
	targets []bridge.BrowserTarget,
	source bridge.BrowserCaptureSource,
	timeoutMs int,
	metadata bridge.BrowserCaptureMetadata,
) (bridge.BrowserCaptureAttempt, bridge.BrowserTarget, error) {
	unavailableCount := 0
	lastUnavailableError := ""

	for _, target := range targets {
		attempt, err := captureBrowserFunc(ctx, target, source, timeoutMs, metadata)
		if err != nil {
			unavailableCount++
			lastUnavailableError = fmt.Sprintf("%s capture failed: %v", browserDisplayName(target), err)
			continue
		}

		if attempt.ExtractionMethod == "browser_extension" {
			return attempt, target, nil
		}
		if attempt.ErrorCode == "ERR_EXTENSION_UNAVAILABLE" {
			unavailableCount++
			lastUnavailableError = describeBrowserAttemptFailure(target, attempt)
			continue
		}

		return bridge.BrowserCaptureAttempt{}, target, fmt.Errorf("%s", describeBrowserAttemptFailure(target, attempt))
	}

	if unavailableCount == len(targets) && len(targets) > 0 {
		if len(targets) > 1 {
			return bridge.BrowserCaptureAttempt{}, "", fmt.Errorf(
				"%s Neither Safari nor Chrome bridge is currently reachable.",
				lastUnavailableError,
			)
		}
		return bridge.BrowserCaptureAttempt{}, "", fmt.Errorf(
			"%s %s bridge is currently unreachable.",
			lastUnavailableError,
			browserDisplayName(targets[0]),
		)
	}

	return bridge.BrowserCaptureAttempt{}, "", fmt.Errorf("capture failed for an unknown reason")
}

type browserCaptureOutput struct {
	Target           string         `json:"target"`
	ExtractionMethod string         `json:"extractionMethod"`
	ErrorCode        string         `json:"errorCode,omitempty"`
	Warnings         []string       `json:"warnings"`
	Markdown         string         `json:"markdown"`
	Payload          map[string]any `json:"payload,omitempty"`
}

func encodeBrowserCaptureOutput(
	format string,
	target bridge.BrowserTarget,
	attempt bridge.BrowserCaptureAttempt,
) ([]byte, error) {
	switch format {
	case formatMarkdown:
		if strings.HasSuffix(attempt.Markdown, "\n") {
			return []byte(attempt.Markdown), nil
		}
		return []byte(attempt.Markdown + "\n"), nil
	case formatJSON:
		return json.MarshalIndent(browserCaptureOutput{
			Target:           string(target),
			ExtractionMethod: attempt.ExtractionMethod,
			ErrorCode:        attempt.ErrorCode,
			Warnings:         attempt.Warnings,
			Markdown:         attempt.Markdown,
			Payload:          attempt.Payload,
		}, "", "  ")
	default:
		return nil, fmt.Errorf("unsupported format: %s", format)
	}
}

func resolveTargetTab(
	ctx context.Context,
	request captureRequest,
	targetOverride bridge.BrowserTarget,
	stderr io.Writer,
) (*osascript.TabEntry, error) {
	browserFilter := ""
	if targetOverride != "" {
		browserFilter = string(targetOverride)
	}

	tabs, warnings, err := listTabsFunc(ctx, browserFilter)
	writeWarnings(stderr, warnings)
	if err != nil {
		return nil, err
	}

	if request.tabReference != "" {
		windowIndex, tabIndex, parseErr := parseTabReference(request.tabReference)
		if parseErr != nil {
			return nil, parseErr
		}
		matched := findTabByIndex(tabs, windowIndex, tabIndex)
		if targetOverride != "" {
			matched = filterTabsByTarget(matched, targetOverride)
		}
		if len(matched) == 0 {
			return nil, fmt.Errorf("no tab found for --tab %s", request.tabReference)
		}
		if len(matched) > 1 {
			return nil, fmt.Errorf("multiple tabs matched --tab %s; pass --browser safari|chrome", request.tabReference)
		}
		return &matched[0], nil
	}

	if request.urlMatch != "" {
		for _, tab := range tabs {
			if strings.Contains(strings.ToLower(tab.URL), strings.ToLower(request.urlMatch)) {
				tabCopy := tab
				return &tabCopy, nil
			}
		}
		return nil, fmt.Errorf("no tab matched --url-match %q", request.urlMatch)
	}

	if request.titleMatch != "" {
		for _, tab := range tabs {
			if strings.Contains(strings.ToLower(tab.Title), strings.ToLower(request.titleMatch)) {
				tabCopy := tab
				return &tabCopy, nil
			}
		}
		return nil, fmt.Errorf("no tab matched --title-match %q", request.titleMatch)
	}

	return nil, fmt.Errorf("missing tab selector")
}

func findTabByIndex(tabs []osascript.TabEntry, windowIndex int, tabIndex int) []osascript.TabEntry {
	matches := []osascript.TabEntry{}
	for _, tab := range tabs {
		if tab.WindowIndex == windowIndex && tab.TabIndex == tabIndex {
			matches = append(matches, tab)
		}
	}
	return matches
}

func filterTabsByTarget(tabs []osascript.TabEntry, target bridge.BrowserTarget) []osascript.TabEntry {
	filtered := []osascript.TabEntry{}
	for _, tab := range tabs {
		if strings.EqualFold(tab.Browser, string(target)) {
			filtered = append(filtered, tab)
		}
	}
	return filtered
}

func parseTabReference(reference string) (windowIndex int, tabIndex int, err error) {
	parts := strings.Split(strings.TrimSpace(reference), ":")
	if len(parts) != 2 {
		return 0, 0, fmt.Errorf("invalid --tab value %q (expected <windowIndex:tabIndex>, e.g. 1:2 or w1:t2)", reference)
	}
	winStr := strings.TrimSpace(parts[0])
	tabStr := strings.TrimSpace(parts[1])
	// Strip optional w/t prefixes (produced by `cgrab list`)
	winStr = strings.TrimPrefix(winStr, "w")
	tabStr = strings.TrimPrefix(tabStr, "t")

	windowIndex, err = strconv.Atoi(winStr)
	if err != nil || windowIndex <= 0 {
		return 0, 0, fmt.Errorf("invalid window index in --tab value %q", reference)
	}
	tabIndex, err = strconv.Atoi(tabStr)
	if err != nil || tabIndex <= 0 {
		return 0, 0, fmt.Errorf("invalid tab index in --tab value %q", reference)
	}
	return windowIndex, tabIndex, nil
}

func findAppByNameMatch(apps []osascript.AppEntry, match string) *osascript.AppEntry {
	needle := strings.ToLower(strings.TrimSpace(match))
	if needle == "" {
		return nil
	}

	for _, app := range apps {
		if strings.Contains(strings.ToLower(app.AppName), needle) {
			appCopy := app
			return &appCopy
		}
	}
	for _, app := range apps {
		if strings.Contains(strings.ToLower(app.BundleIdentifier), needle) {
			appCopy := app
			return &appCopy
		}
	}
	return nil
}

func resolveBrowserTargetOverrideEnv() (bridge.BrowserTarget, error) {
	raw := strings.ToLower(strings.TrimSpace(os.Getenv("CONTEXT_GRABBER_BROWSER_TARGET")))
	return parseOptionalBrowserTarget(raw)
}

func parseOptionalBrowserTarget(raw string) (bridge.BrowserTarget, error) {
	normalized := strings.ToLower(strings.TrimSpace(raw))
	switch normalized {
	case "":
		return "", nil
	case "safari":
		return bridge.BrowserTargetSafari, nil
	case "chrome":
		return bridge.BrowserTargetChrome, nil
	default:
		return "", fmt.Errorf("unsupported browser %q (expected safari or chrome)", raw)
	}
}

func focusedTargetOrder(override bridge.BrowserTarget) []bridge.BrowserTarget {
	if override != "" {
		return []bridge.BrowserTarget{override}
	}
	return []bridge.BrowserTarget{bridge.BrowserTargetSafari, bridge.BrowserTargetChrome}
}

func toBrowserCaptureSource(method string) (bridge.BrowserCaptureSource, error) {
	switch strings.ToLower(strings.TrimSpace(method)) {
	case "", "auto":
		return bridge.BrowserCaptureSourceAuto, nil
	case "applescript":
		return bridge.BrowserCaptureSourceLive, nil
	case "extension":
		return bridge.BrowserCaptureSourceRuntime, nil
	default:
		return "", fmt.Errorf(
			"unsupported browser --method value %q (expected auto, applescript, or extension)",
			method,
		)
	}
}

func toDesktopCaptureMethod(method string) (bridge.DesktopCaptureMethod, error) {
	switch strings.ToLower(strings.TrimSpace(method)) {
	case "", "auto", "applescript":
		return bridge.DesktopCaptureMethodAuto, nil
	case "ax":
		return bridge.DesktopCaptureMethodAX, nil
	case "ocr":
		return bridge.DesktopCaptureMethodOCR, nil
	default:
		return "", fmt.Errorf(
			"unsupported desktop --method value %q (expected auto, applescript, ax, or ocr)",
			method,
		)
	}
}

func browserDisplayName(target bridge.BrowserTarget) string {
	if target == bridge.BrowserTargetSafari {
		return "Safari"
	}
	return "Chrome"
}

func describeBrowserAttemptFailure(target bridge.BrowserTarget, attempt bridge.BrowserCaptureAttempt) string {
	warning := "Unknown capture error."
	if len(attempt.Warnings) > 0 && strings.TrimSpace(attempt.Warnings[0]) != "" {
		warning = strings.TrimSpace(attempt.Warnings[0])
	}
	code := attempt.ErrorCode
	if strings.TrimSpace(code) == "" {
		code = "ERR_EXTENSION_UNAVAILABLE"
	}
	return fmt.Sprintf("%s capture failed (%s): %s", browserDisplayName(target), code, warning)
}

func resolveDefaultCaptureOutputFilePath(format string) (string, error) {
	settings, err := config.LoadSettings()
	if err != nil {
		return "", err
	}
	_, captureDir, err := config.EnsureBaseLayout(settings)
	if err != nil {
		return "", err
	}

	timestamp := nowFunc().UTC().Format("20060102-150405.000")
	extension := ".md"
	if format == formatJSON {
		extension = ".json"
	}

	return filepath.Join(captureDir, "capture-"+timestamp+extension), nil
}
