package cmd

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/anthonylu23/context_grabber/cgrab/internal/config"
	"golang.org/x/term"
)

const (
	defaultCardWidth = 56
	minCardWidth     = 40
	maxCardWidth     = 80
)

func detectCardWidth(out io.Writer) int {
	// Prefer the actual output stream (e.g. when help goes to stdout)
	if f, ok := out.(*os.File); ok {
		if w, _, err := term.GetSize(int(f.Fd())); err == nil && w >= minCardWidth {
			return clampWidth(w)
		}
	}
	// Fallback: try stdout, then stderr
	for _, f := range []*os.File{os.Stdout, os.Stderr} {
		if w, _, err := term.GetSize(int(f.Fd())); err == nil && w >= minCardWidth {
			return clampWidth(w)
		}
	}
	// Fallback: COLUMNS env (set by many shells)
	if s := os.Getenv("COLUMNS"); s != "" {
		if w, err := strconv.Atoi(strings.TrimSpace(s)); err == nil && w >= minCardWidth {
			return clampWidth(w)
		}
	}
	return defaultCardWidth
}

func clampWidth(w int) int {
	if w > maxCardWidth {
		return maxCardWidth
	}
	return w
}

func buildProductCard(width int) string {
	baseDir := "—"
	captureDir := "—"

	settings, err := config.LoadSettings()
	if err == nil {
		if bd, e := config.ResolveBaseDir(); e == nil {
			baseDir = shortenPath(bd, width)
		}
		if _, cd, e := config.EnsureBaseLayout(settings); e == nil {
			captureDir = shortenPath(cd, width)
		}
	}

	title := "ContextGrabber 🤏"
	lines := []string{
		"",
		fmt.Sprintf("base_dir    %s", baseDir),
		fmt.Sprintf("output_dir  %s", captureDir),
		fmt.Sprintf("version     %s", Version),
	}

	pad := width - 4
	var b strings.Builder
	b.WriteString("╭" + strings.Repeat("─", width-2) + "╮\n")
	b.WriteString("│ " + padRight(title, pad) + " │\n")
	b.WriteString("│" + strings.Repeat(" ", width-2) + "│\n")
	for _, line := range lines {
		b.WriteString("│ " + padRight(line, pad) + " │\n")
	}
	b.WriteString("╰" + strings.Repeat("─", width-2) + "╯")
	return b.String()
}

func shortenPath(p string, cardWidth int) string {
	maxLen := cardWidth - 14
	if maxLen < 4 {
		maxLen = 4
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return truncate(p, maxLen)
	}
	if rel, err := filepath.Rel(home, p); err == nil && !strings.HasPrefix(rel, "..") {
		return truncate("~"+string(filepath.Separator)+rel, maxLen)
	}
	return truncate(p, maxLen)
}

func displayWidth(s string) int {
	w := 0
	for _, r := range s {
		if r > '\U0000FFFF' {
			w += 2
		} else {
			w++
		}
	}
	return w
}

func truncate(s string, max int) string {
	if displayWidth(s) <= max {
		return s
	}
	runes := []rune(s)
	for displayWidth(string(runes))+3 > max && len(runes) > 0 {
		runes = runes[:len(runes)-1]
	}
	return string(runes) + "..."
}

func padRight(s string, width int) string {
	dw := displayWidth(s)
	if dw >= width {
		return s
	}
	return s + strings.Repeat(" ", width-dw)
}
