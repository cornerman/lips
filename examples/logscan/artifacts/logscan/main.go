package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"strconv"
	"strings"
)

// asString renders a decoded JSON value the way it is written on the
// command line, so that a=1 matches both {"a":"1"} and {"a":1}.
func asString(v interface{}) string {
	switch t := v.(type) {
	case string:
		return t
	case bool:
		if t {
			return "true"
		}
		return "false"
	case float64:
		return strconv.FormatFloat(t, 'f', -1, 64)
	case nil:
		return "null"
	}
	b, err := json.Marshal(v)
	if err != nil {
		return ""
	}
	return string(b)
}

func main() {
	want := map[string]string{}
	for _, arg := range os.Args[1:] {
		k, v, found := strings.Cut(arg, "=")
		if !found {
			fmt.Fprintf(os.Stderr, "expected field=value, got %q\n", arg)
			os.Exit(2)
		}
		want[k] = v
	}

	in := bufio.NewScanner(os.Stdin)
	in.Buffer(make([]byte, 0, 64*1024), 16*1024*1024)
	out := bufio.NewWriter(os.Stdout)
	defer out.Flush()

	for in.Scan() {
		line := in.Text()
		if strings.TrimSpace(line) == "" {
			continue
		}
		var rec map[string]interface{}
		if err := json.Unmarshal([]byte(line), &rec); err != nil {
			continue
		}
		keep := true
		for k, v := range want {
			got, ok := rec[k]
			if !ok || asString(got) != v {
				keep = false
				break
			}
		}
		if keep {
			fmt.Fprintln(out, line)
		}
	}
	if err := in.Err(); err != nil {
		out.Flush()
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}