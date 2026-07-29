package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"strings"
)

func main() {
	conditions := map[string]string{}
	for _, arg := range os.Args[1:] {
		parts := strings.SplitN(arg, "=", 2)
		if len(parts) != 2 {
			fmt.Fprintf(os.Stderr, "invalid argument: %s\n", arg)
			os.Exit(1)
		}
		conditions[parts[0]] = parts[1]
	}

	scanner := bufio.NewScanner(os.Stdin)
	scanner.Buffer(make([]byte, 1024*1024), 1024*1024*10)
	for scanner.Scan() {
		line := scanner.Text()
		var obj map[string]interface{}
		if err := json.Unmarshal([]byte(line), &obj); err != nil {
			continue
		}
		keep := true
		for field, want := range conditions {
			val, ok := obj[field]
			if !ok {
				keep = false
				break
			}
			var s string
			switch v := val.(type) {
			case string:
				s = v
			default:
				b, _ := json.Marshal(v)
				s = string(b)
			}
			if s != want {
				keep = false
				break
			}
		}
		if keep {
			fmt.Println(line)
		}
	}
}