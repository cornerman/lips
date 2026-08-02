package main

import (
	"bufio"
	"fmt"
	"os"
	"strings"
	"time"
)

const (
	markLogged  = "@mark_logged@"
	markMissing = "@mark_missing@"
	layout      = "2006-01-02"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: @name@ HABIT [LOGFILE]")
		os.Exit(2)
	}
	want := os.Args[1]

	in := os.Stdin
	if len(os.Args) > 2 {
		f, err := os.Open(os.Args[2])
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		defer f.Close()
		in = f
	}

	logged := map[string]bool{}
	var first, last time.Time
	sc := bufio.NewScanner(in)
	for sc.Scan() {
		line := strings.TrimRight(sc.Text(), "\r")
		if strings.TrimSpace(line) == "" {
			continue
		}
		parts := strings.SplitN(line, "\t", 2)
		if len(parts) != 2 {
			continue
		}
		day, err := time.Parse(layout, strings.TrimSpace(parts[0]))
		if err != nil {
			continue
		}
		name := strings.TrimSpace(parts[1])
		if first.IsZero() || day.Before(first) {
			first = day
		}
		if last.IsZero() || day.After(last) {
			last = day
		}
		if name == want {
			logged[day.Format(layout)] = true
		}
	}
	if err := sc.Err(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	if first.IsZero() {
		fmt.Println("")
		return
	}
	var out strings.Builder
	for d := first; !d.After(last); d = d.AddDate(0, 0, 1) {
		if logged[d.Format(layout)] {
			out.WriteString(markLogged)
		} else {
			out.WriteString(markMissing)
		}
	}
	fmt.Println(out.String())
}