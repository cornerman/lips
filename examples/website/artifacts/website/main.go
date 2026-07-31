package main

import (
	"html/template"
	"log"
	"net/http"
	"os"
)

type page struct {
	CanvasID     string
	CanvasText   string
	ButtonLabel  string
	ButtonAction string
	ButtonTarget string
}

func env(name, fallback string) string {
	if v := os.Getenv(name); v != "" {
		return v
	}
	return fallback
}

var pageTemplate = template.Must(template.New("page").Parse(`<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>{{.CanvasID}}</title>
<style>
body { font-family: sans-serif; margin: 2rem; }
svg { border: 1px solid #ccc; background: #fff; }
figcaption { color: #555; margin-top: 0.5rem; }
button { margin-top: 1rem; padding: 0.6rem 1.2rem; font-size: 1rem; }
</style>
</head>
<body>
<figure>
<svg id="{{.CanvasID}}" width="640" height="400" role="img" aria-label="{{.CanvasText}}"></svg>
<figcaption>{{.CanvasText}}</figcaption>
</figure>
<button id="repaint" title="{{.ButtonAction}}">{{.ButtonLabel}}</button>
<script>
var target = "{{.ButtonTarget}}";
function rnd(n) { return Math.floor(Math.random() * n); }
function colour(alpha) {
  return "rgba(" + rnd(256) + "," + rnd(256) + "," + rnd(256) + "," + alpha + ")";
}
function paint() {
  var svg = document.getElementById(target);
  if (!svg) { return; }
  while (svg.firstChild) { svg.removeChild(svg.firstChild); }
  var ns = "http://www.w3.org/2000/svg";
  var count = 6 + rnd(12);
  for (var i = 0; i < count; i++) {
    var kind = rnd(3);
    var el;
    if (kind === 0) {
      el = document.createElementNS(ns, "circle");
      el.setAttribute("cx", rnd(640));
      el.setAttribute("cy", rnd(400));
      el.setAttribute("r", 10 + rnd(90));
    } else if (kind === 1) {
      el = document.createElementNS(ns, "rect");
      el.setAttribute("x", rnd(600));
      el.setAttribute("y", rnd(360));
      el.setAttribute("width", 20 + rnd(200));
      el.setAttribute("height", 20 + rnd(160));
    } else {
      el = document.createElementNS(ns, "line");
      el.setAttribute("x1", rnd(640));
      el.setAttribute("y1", rnd(400));
      el.setAttribute("x2", rnd(640));
      el.setAttribute("y2", rnd(400));
      el.setAttribute("stroke-width", 1 + rnd(8));
      el.setAttribute("stroke", colour("1"));
    }
    el.setAttribute("fill", colour("0.6"));
    svg.appendChild(el);
  }
}
document.getElementById("repaint").addEventListener("click", paint);
paint();
</script>
</body>
</html>
`))

func main() {
	p := page{
		CanvasID:     env("CANVAS_ID", "canvas"),
		CanvasText:   env("CANVAS_CAPTION", ""),
		ButtonLabel:  env("BUTTON_LABEL", "again"),
		ButtonAction: env("BUTTON_ACTION", ""),
		ButtonTarget: env("BUTTON_TARGET", env("CANVAS_ID", "canvas")),
	}
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/" {
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		if err := pageTemplate.Execute(w, p); err != nil {
			log.Print(err)
		}
	})
	addr := ":" + env("PORT", "8080")
	log.Printf("serving on %s", addr)
	log.Fatal(http.ListenAndServe(addr, nil))
}