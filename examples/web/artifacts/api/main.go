package main

import (
	"net/http"
	"os"
	"path/filepath"
	"strconv"
)

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	base := "/etc/http-routes"
	mux := http.NewServeMux()
	entries, err := os.ReadDir(base)
	if err == nil {
		for _, e := range entries {
			if !e.IsDir() {
				continue
			}
			name := e.Name()
			statusBytes, err1 := os.ReadFile(filepath.Join(base, name, "status"))
			bodyBytes, err2 := os.ReadFile(filepath.Join(base, name, "body"))
			if err1 != nil || err2 != nil {
				continue
			}
			status, errS := strconv.Atoi(string(statusBytes))
			if errS != nil {
				status = 200
			}
			body := string(bodyBytes)
			routePath := "/" + name
			mux.HandleFunc(routePath, func(w http.ResponseWriter, r *http.Request) {
				w.WriteHeader(status)
				w.Write([]byte(body))
			})
		}
	}
	http.ListenAndServe(":"+port, mux)
}