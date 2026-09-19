// Package ui provides small, consistent, good-looking terminal output
// helpers built on lipgloss. Everything degrades gracefully when the output
// is not a TTY or when colour is disabled.
package ui

import (
	"fmt"
	"io"
	"os"
	"strings"

	"github.com/charmbracelet/lipgloss"
)

// Theme holds the styles used across the CLI.
type Theme struct {
	Title   lipgloss.Style
	Subtle  lipgloss.Style
	Accent  lipgloss.Style
	Success lipgloss.Style
	Warn    lipgloss.Style
	Error   lipgloss.Style
	Badge   lipgloss.Style
	Key     lipgloss.Style
}

// UI writes styled output to a writer.
type UI struct {
	w     io.Writer
	theme Theme
}

// New returns a UI writing to w. When noColor is true (or w is not a TTY),
// styling is disabled.
func New(w io.Writer, noColor bool) *UI {
	if noColor || !isTerminal(w) {
		lipgloss.SetColorProfile(0) // Ascii / no colour
	}
	return &UI{w: w, theme: defaultTheme()}
}

// Default returns a UI writing to stdout with auto colour detection.
func Default() *UI { return New(os.Stdout, os.Getenv("NO_COLOR") != "") }

func defaultTheme() Theme {
	return Theme{
		Title:   lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("#7D56F4")),
		Subtle:  lipgloss.NewStyle().Foreground(lipgloss.Color("244")),
		Accent:  lipgloss.NewStyle().Foreground(lipgloss.Color("#04B575")),
		Success: lipgloss.NewStyle().Foreground(lipgloss.Color("#04B575")).Bold(true),
		Warn:    lipgloss.NewStyle().Foreground(lipgloss.Color("#FFB454")).Bold(true),
		Error:   lipgloss.NewStyle().Foreground(lipgloss.Color("#FF5F87")).Bold(true),
		Badge:   lipgloss.NewStyle().Foreground(lipgloss.Color("#1A1A1A")).Background(lipgloss.Color("#7D56F4")).Padding(0, 1).Bold(true),
		Key:     lipgloss.NewStyle().Foreground(lipgloss.Color("#00D7FF")),
	}
}

// Banner prints the application banner with a subtitle.
func (u *UI) Banner(name, version, subtitle string) {
	fmt.Fprintln(u.w, u.theme.Badge.Render(" "+name+" ")+" "+u.theme.Subtle.Render(version))
	if subtitle != "" {
		fmt.Fprintln(u.w, u.theme.Subtle.Render(subtitle))
	}
	fmt.Fprintln(u.w)
}

// Section prints a section heading.
func (u *UI) Section(title string) {
	fmt.Fprintln(u.w, u.theme.Title.Render("▌ "+title))
}

// Info prints a plain informational line.
func (u *UI) Info(format string, a ...any) {
	fmt.Fprintln(u.w, fmt.Sprintf(format, a...))
}

// Step prints an in-progress action line.
func (u *UI) Step(format string, a ...any) {
	fmt.Fprintln(u.w, u.theme.Accent.Render("→")+" "+fmt.Sprintf(format, a...))
}

// Success prints a success line.
func (u *UI) Success(format string, a ...any) {
	fmt.Fprintln(u.w, u.theme.Success.Render("✔")+" "+fmt.Sprintf(format, a...))
}

// Warn prints a warning line.
func (u *UI) Warn(format string, a ...any) {
	fmt.Fprintln(u.w, u.theme.Warn.Render("!")+" "+fmt.Sprintf(format, a...))
}

// Error prints an error line to the writer.
func (u *UI) Error(format string, a ...any) {
	fmt.Fprintln(u.w, u.theme.Error.Render("✘")+" "+fmt.Sprintf(format, a...))
}

// Skip prints a skipped/no-op line.
func (u *UI) Skip(format string, a ...any) {
	fmt.Fprintln(u.w, u.theme.Subtle.Render("·")+" "+u.theme.Subtle.Render(fmt.Sprintf(format, a...)))
}

// KeyVal prints an aligned key/value pair.
func (u *UI) KeyVal(key, val string) {
	fmt.Fprintf(u.w, "  %s %s\n", u.theme.Key.Render(fmt.Sprintf("%-12s", key)), val)
}

// Table renders a simple aligned table with a header row.
func (u *UI) Table(headers []string, rows [][]string) {
	widths := make([]int, len(headers))
	for i, h := range headers {
		widths[i] = lipgloss.Width(h)
	}
	for _, row := range rows {
		for i, cell := range row {
			if i < len(widths) && lipgloss.Width(cell) > widths[i] {
				widths[i] = lipgloss.Width(cell)
			}
		}
	}

	var head strings.Builder
	for i, h := range headers {
		head.WriteString(u.theme.Subtle.Render(pad(h, widths[i])))
		if i < len(headers)-1 {
			head.WriteString("  ")
		}
	}
	fmt.Fprintln(u.w, head.String())

	for _, row := range rows {
		var line strings.Builder
		for i, cell := range row {
			w := 0
			if i < len(widths) {
				w = widths[i]
			}
			line.WriteString(pad(cell, w))
			if i < len(row)-1 {
				line.WriteString("  ")
			}
		}
		fmt.Fprintln(u.w, line.String())
	}
}

// Styles exposes the theme for callers that need to style inline fragments.
func (u *UI) Styles() Theme { return u.theme }

// pad right-pads s to width w accounting for display width.
func pad(s string, w int) string {
	gap := w - lipgloss.Width(s)
	if gap <= 0 {
		return s
	}
	return s + strings.Repeat(" ", gap)
}

func isTerminal(w io.Writer) bool {
	f, ok := w.(*os.File)
	if !ok {
		return false
	}
	fi, err := f.Stat()
	if err != nil {
		return false
	}
	return (fi.Mode() & os.ModeCharDevice) != 0
}
