package main

import (
	"fmt"
	"os"
	"strconv"
)

// @fname@ takes one string and writes it to stdout, as the program declares.
func @fname@(x string) {
	fmt.Println(x)
}

// The program's calls are handed to this binary in order, as the environment
// variables CALL_1, CALL_2, ... set on the systemd unit that runs it.
func main() {
	for i := 1; i <= 1024; i++ {
		if v, ok := os.LookupEnv("CALL_" + strconv.Itoa(i)); ok {
			@fname@(v)
		}
	}
}