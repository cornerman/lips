package main

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

func configDir() string {
	if v := os.Getenv("XDG_CONFIG_HOME"); v != "" {
		return v
	}
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".config")
}

func readConfig(name string) (string, error) {
	p := filepath.Join(configDir(), name)
	data, err := os.ReadFile(p)
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(data)), nil
}

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: habit <name>")
		os.Exit(1)
	}
	target := os.Args[1]

	logPath, err := readConfig("habit-logpath")
	if err != nil || logPath == "" {
		fmt.Fprintln(os.Stderr, "habit: no log path configured (habit-logpath)")
		os.Exit(1)
	}

	days := 365
	if s, err := readConfig("habit-heatmapdays"); err == nil && s != "" {
		if n, err := strconv.Atoi(s); err == nil && n > 0 {
			days = n
		}
	}

	seen := map[string]bool{}

	f, err := os.Open(logPath)
	if err == nil {
		defer f.Close()
		sc := bufio.NewScanner(f)
		for sc.Scan() {
			line := sc.Text()
			if line == "" {
				continue
			}
			parts := strings.SplitN(line, "\t", 2)
			if len(parts) != 2 {
				continue
			}
			date, habit := strings.TrimSpace(parts[0]), strings.TrimSpace(parts[1])
			if habit == target {
				seen[date] = true
			}
		}
	}

	today := time.Now().UTC().Truncate(24 * time.Hour)
	for i := days - 1; i >= 0; i-- {
		d := today.AddDate(0, 0, -i)
		key := d.Format("2006-01-02")
		if seen[key] {
			fmt.Print("#")
		} else {
			fmt.Print(".")
		}
		if d.Weekday() == time.Saturday {
			fmt.Println()
		}
	}
	fmt.Println()
}