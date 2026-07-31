package main

import (
	"fmt"
	"math/rand"
	"net/http"
	"os"
)

func randomSVG() string {
	w, h := 300, 300
	svg := fmt.Sprintf("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"%d\" height=\"%d\">", w, h)
	for i := 0; i < 8; i++ {
		cx := rand.Intn(w)
		cy := rand.Intn(h)
		r := rand.Intn(40) + 10
		color := fmt.Sprintf("#%06x", rand.Intn(0xffffff))
		svg += fmt.Sprintf("<circle cx=\"%d\" cy=\"%d\" r=\"%d\" fill=\"%s\" />", cx, cy, r, color)
	}
	svg += "</svg>"
	return svg
}

const page = `<!DOCTYPE html>
<html>
<head><title>@module_name@</title></head>
<body>
<div id="@canvas_name@">%s</div>
<button onclick="refresh()">@button_label@</button>
<script>
function refresh() {
  fetch('/random').then(function(r) { return r.text(); }).then(function(svg) {
    document.getElementById('@button_target@').innerHTML = svg;
  });
}
</script>
</body>
</html>`

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, page, randomSVG())
	})
	http.HandleFunc("/random", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "image/svg+xml")
		fmt.Fprint(w, randomSVG())
	})
	http.ListenAndServe(":"+port, nil)
}