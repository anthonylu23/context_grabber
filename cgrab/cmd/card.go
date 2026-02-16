package cmd

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/anthonylu23/context_grabber/cgrab/internal/config"
	"github.com/charmbracelet/lipgloss"
	"golang.org/x/term"
)

const (
	defaultCardWidth = 56
	minCardWidth     = 20
	maxCardWidth     = 80
	borderedCardMin  = 52
)

func detectCardWidth(out io.Writer) int {
	// Prefer the actual output stream (e.g. when help goes to stdout)
	if f, ok := out.(*os.File); ok {
		if w, _, err := term.GetSize(int(f.Fd())); err == nil && w > 0 {
			return clampWidth(w)
		}
	}
	// Fallback: try stdout, then stderr
	for _, f := range []*os.File{os.Stdout, os.Stderr} {
		if w, _, err := term.GetSize(int(f.Fd())); err == nil && w > 0 {
			return clampWidth(w)
		}
	}
	// Fallback: COLUMNS env (set by many shells)
	if s := os.Getenv("COLUMNS"); s != "" {
		if w, err := strconv.Atoi(strings.TrimSpace(s)); err == nil && w > 0 {
			return clampWidth(w)
		}
	}
	return defaultCardWidth
}

func clampWidth(w int) int {
	if w < minCardWidth {
		return minCardWidth
	}
	if w > maxCardWidth {
		return maxCardWidth
	}
	return w
}

func buildProductCard(width int) string {
	useBorder := width >= borderedCardMin
	contentWidth := width
	if useBorder {
		contentWidth = width - 4
	}
	if contentWidth < 1 {
		contentWidth = 1
	}

	baseDir := "—"
	captureDir := "—"

	settings, err := config.LoadSettings()
	if err == nil {
		if bd, e := config.ResolveBaseDir(); e == nil {
			baseDir = shortenPath(bd, valueWidth(contentWidth))
		}
		if _, cd, e := config.EnsureBaseLayout(settings); e == nil {
			captureDir = shortenPath(cd, valueWidth(contentWidth))
		}
	}

	title := "ContextGrabber 🤏"
	lines := []string{
		title,
		"",
		fmt.Sprintf("base_dir    %s", baseDir),
		fmt.Sprintf("output_dir  %s", captureDir),
		fmt.Sprintf("version     %s", Version),
	}

	lineStyle := lipgloss.NewStyle().Width(contentWidth)
	formattedLines := make([]string, 0, len(lines))
	for _, line := range lines {
		formattedLines = append(formattedLines, lineStyle.Render(line))
	}

	if !useBorder {
		return strings.Join(formattedLines, "\n")
	}

	cardStyle := lipgloss.NewStyle().
		BorderStyle(lipgloss.RoundedBorder()).
		Padding(0, 1)
	return cardStyle.Render(strings.Join(formattedLines, "\n"))
}

func valueWidth(contentWidth int) int {
	rowKeyWidth := lipgloss.Width("output_dir  ")
	maxLen := contentWidth - rowKeyWidth
	if maxLen < 4 {
		maxLen = 4
	}
	return maxLen
}

func shortenPath(p string, maxLen int) string {
	home, err := os.UserHomeDir()
	if err != nil {
		return truncate(p, maxLen)
	}
	if rel, err := filepath.Rel(home, p); err == nil && !strings.HasPrefix(rel, "..") {
		return truncate("~"+string(filepath.Separator)+rel, maxLen)
	}
	return truncate(p, maxLen)
}

func truncate(s string, max int) string {
	if max <= 0 {
		return ""
	}
	if lipgloss.Width(s) <= max {
		return s
	}
	if max <= 3 {
		return strings.Repeat(".", max)
	}
	runes := []rune(s)
	for len(runes) > 0 && lipgloss.Width(string(runes))+3 > max {
		runes = runes[:len(runes)-1]
	}
	if len(runes) == 0 {
		return strings.Repeat(".", 3)
	}
	return string(runes) + "..."
}
