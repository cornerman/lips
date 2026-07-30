package main

import (
	"fmt"
	"net/http"
	"os"
)

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	text := os.Getenv("RESPONSE_TEXT")

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprint(w, text)
	})

	if err := http.ListenAndServe(":"+port, nil); err != nil {
		panic(err)
	}
}