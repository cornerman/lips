package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"strings"
)

func main() {
	filters := map[string]string{}
	for _, arg := range os.Args[1:] {
		parts := strings.SplitN(arg, "=", 2)
		if len(parts) == 2 {
			filters[parts[0]] = parts[1]
		}
	}

	scanner := bufio.NewScanner(os.Stdin)
	buf := make([]byte, 1024*1024)
	scanner.Buffer(buf, len(buf))

	for scanner.Scan() {
		line := scanner.Text()

		var obj map[string]interface{}
		if err := json.Unmarshal([]byte(line), &obj); err != nil {
			continue
		}

		keep := true
		for k, want := range filters {
			raw, ok := obj[k]
			if !ok {
				keep = false
				break
			}
			var got string
			switch v := raw.(type) {
			case string:
				got = v
			default:
				b, _ := json.Marshal(v)
				got = string(b)
			}
			if got != want {
				keep = false
				break
			}
		}

		if keep {
			fmt.Println(line)
		}
	}
}