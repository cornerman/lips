package main

// A one-response http server. Both values below are written in by lips at
// compile time from the .lips program: the port it listens on and the text
// every request is answered with.

import (
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"strings"
)

const listenPort = "@port@"
const responseBody = "@body@"

func handler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	io.WriteString(w, responseBody)
}

// selfCheck serves one request to itself on a loopback port picked by the
// kernel and prints the response body. It needs no configured port and no
// running service, so the program's own example line can be observed.
func selfCheck(path string) {
	if !strings.HasPrefix(path, "/") {
		path = "/" + path
	}
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		log.Fatalf("self-check listen: %v", err)
	}
	defer ln.Close()
	srv := &http.Server{Handler: http.HandlerFunc(handler)}
	go srv.Serve(ln)
	resp, err := http.Get("http://" + ln.Addr().String() + path)
	if err != nil {
		log.Fatalf("self-check request: %v", err)
	}
	defer resp.Body.Close()
	out, err := io.ReadAll(resp.Body)
	if err != nil {
		log.Fatalf("self-check read: %v", err)
	}
	fmt.Println(string(out))
}

func main() {
	check := flag.String("check", "", "answer one request for the given path on stdout, then exit")
	flag.Parse()
	if *check != "" {
		selfCheck(*check)
		return
	}
	addr := ":" + listenPort
	log.Printf("answering every request with %q on %s", responseBody, addr)
	if err := http.ListenAndServe(addr, http.HandlerFunc(handler)); err != nil {
		log.Fatalf("listen: %v", err)
	}
}