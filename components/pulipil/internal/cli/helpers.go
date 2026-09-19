package cli

import "strconv"

func itoa(n int) string { return strconv.Itoa(n) }

func join(items []string) string {
	out := ""
	for i, s := range items {
		if i > 0 {
			out += ", "
		}
		out += s
	}
	return out
}
