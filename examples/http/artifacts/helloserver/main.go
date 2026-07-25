package main

import (
	"net/http"
	"os"
)

func main() {
	response := os.Getenv("RESPONSE")
	addr := ":" + os.Getenv("PORT")
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte(response))
	})
	http.ListenAndServe(addr, nil)
}