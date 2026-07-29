package main

import (
	"bufio"
	"fmt"
	"os"
	"strings"
)

func main() {
	path := os.Getenv("BOARD_PATH")
	if path == "" {
		fmt.Fprintln(os.Stderr, "BOARD_PATH is not set")
		os.Exit(1)
	}
	colsEnv := os.Getenv("BOARD_COLUMNS")
	if colsEnv == "" {
		fmt.Fprintln(os.Stderr, "BOARD_COLUMNS is not set")
		os.Exit(1)
	}

	var columns []string
	for _, c := range strings.Split(colsEnv, ",") {
		c = strings.TrimSpace(c)
		if c != "" {
			columns = append(columns, c)
		}
	}

	items := make(map[string][]string)
	for _, c := range columns {
		items[c] = nil
	}

	f, err := os.Open(path)
	if err != nil {
		fmt.Fprintln(os.Stderr, "cannot open board file:", err)
		os.Exit(1)
	}
	defer f.Close()

	scanner := bufio.NewScanner(f)
	current := ""
	for scanner.Scan() {
		line := scanner.Text()
		trimmed := strings.TrimSpace(line)
		if strings.HasPrefix(trimmed, "#") {
			heading := strings.TrimSpace(strings.TrimLeft(trimmed, "#"))
			current = ""
			for _, c := range columns {
				if strings.EqualFold(heading, c) {
					current = c
					break
				}
			}
			continue
		}
		if current == "" {
			continue
		}
		if strings.HasPrefix(trimmed, "-") || strings.HasPrefix(trimmed, "*") {
			item := strings.TrimSpace(trimmed[1:])
			if item != "" {
				items[current] = append(items[current], item)
			}
		}
	}

	printBoard(columns, items)
}

func printBoard(columns []string, items map[string][]string) {
	widths := make([]int, len(columns))
	for i, c := range columns {
		w := len(c)
		for _, it := range items[c] {
			if len(it) > w {
				w = len(it)
			}
		}
		widths[i] = w
	}

	for i, c := range columns {
		fmt.Printf("%-*s  ", widths[i], strings.ToUpper(c))
	}
	fmt.Println()
	for i := range columns {
		fmt.Print(strings.Repeat("-", widths[i]), "  ")
	}
	fmt.Println()

	max := 0
	for _, c := range columns {
		if len(items[c]) > max {
			max = len(items[c])
		}
	}
	for row := 0; row < max; row++ {
		for i, c := range columns {
			val := ""
			if row < len(items[c]) {
				val = items[c][row]
			}
			fmt.Printf("%-*s  ", widths[i], val)
		}
		fmt.Println()
	}
}