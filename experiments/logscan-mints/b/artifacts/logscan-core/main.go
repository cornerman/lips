package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"strconv"
	"strings"
)

// matchRule is filled in at build time: "every" or "any".
const matchRule = "@match@"

type fieldTest struct {
	field string
	want  string
}

func parseTests(args []string) []fieldTest {
	tests := make([]fieldTest, 0, len(args))
	for _, a := range args {
		i := strings.Index(a, "=")
		if i < 1 {
			fmt.Fprintf(os.Stderr, "expected field=value, got %s\n", a)
			os.Exit(2)
		}
		tests = append(tests, fieldTest{field: a[:i], want: a[i+1:]})
	}
	return tests
}

func asText(v interface{}) (string, bool) {
	switch t := v.(type) {
	case string:
		return t, true
	case bool:
		return strconv.FormatBool(t), true
	case float64:
		return strconv.FormatFloat(t, 'f', -1, 64), true
	case nil:
		return "null", true
	default:
		return "", false
	}
}

func keep(line string, tests []fieldTest) bool {
	var rec map[string]interface{}
	if err := json.Unmarshal([]byte(line), &rec); err != nil {
		return false
	}
	if len(tests) == 0 {
		return matchRule == "every"
	}
	for _, t := range tests {
		v, ok := rec[t.field]
		hit := false
		if ok {
			if s, textual := asText(v); textual && s == t.want {
				hit = true
			}
		}
		if matchRule == "every" && !hit {
			return false
		}
		if matchRule == "any" && hit {
			return true
		}
	}
	return matchRule == "every"
}

func main() {
	if matchRule != "every" && matchRule != "any" {
		fmt.Fprintf(os.Stderr, "unknown match rule %s\n", matchRule)
		os.Exit(2)
	}
	tests := parseTests(os.Args[1:])
	in := bufio.NewScanner(os.Stdin)
	in.Buffer(make([]byte, 0, 64*1024), 16*1024*1024)
	out := bufio.NewWriter(os.Stdout)
	for in.Scan() {
		line := in.Text()
		if keep(line, tests) {
			fmt.Fprintln(out, line)
		}
	}
	err := in.Err()
	out.Flush()
	if err != nil {
		fmt.Fprintf(os.Stderr, "read error: %v\n", err)
		os.Exit(1)
	}
}