package main

import (
	"fmt"
	"os"
	"strconv"
)

// println_to_stdout is the function the program declares: it takes one
// string parameter and writes it, followed by a newline, to stdout.
func println_to_stdout(@param@ string) {
	fmt.Println(@param@)
}

// main replays the program's calls in order. Each call is handed to the
// binary through the environment as CALL_1, CALL_2, ... -- one variable per
// call, holding that call's string argument. The loop stops at the first
// missing index, so the number of calls is decided entirely by the
// environment the systemd unit carries.
func main() {
	for i := 1; ; i++ {
		arg, ok := os.LookupEnv("CALL_" + strconv.Itoa(i))
		if !ok {
			return
		}
		println_to_stdout(arg)
	}
}