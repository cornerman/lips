package main

import (
	"html/template"
	"log"
	"net/http"
	"os"
	"sort"
	"strconv"
	"strings"
)

// The website program's canvases and buttons reach this server as environment
// variables of the shape CANVAS_<key>_<field> and BUTTON_<key>_<field>, one
// variable per stated word. <key> is the item's position in the program, so
// sorting the keys numerically restores the order the program wrote them in.
type record struct {
	Key    string
	Fields map[string]string
}

func records(prefix string) []record {
	byKey := map[string]map[string]string{}
	for _, kv := range os.Environ() {
		eq := strings.IndexByte(kv, '=')
		if eq < 0 {
			continue
		}
		name := kv[:eq]
		value := kv[eq+1:]
		if !strings.HasPrefix(name, prefix+"_") {
			continue
		}
		rest := name[len(prefix)+1:]
		cut := strings.LastIndexByte(rest, '_')
		if cut <= 0 || cut+1 >= len(rest) {
			continue
		}
		key := rest[:cut]
		field := strings.ToLower(rest[cut+1:])
		if byKey[key] == nil {
			byKey[key] = map[string]string{}
		}
		byKey[key][field] = value
	}
	keys := make([]string, 0, len(byKey))
	for k := range byKey {
		keys = append(keys, k)
	}
	sort.Slice(keys, func(a, b int) bool {
		na, erra := strconv.Atoi(keys[a])
		nb, errb := strconv.Atoi(keys[b])
		if erra == nil && errb == nil {
			return na < nb
		}
		return keys[a] < keys[b]
	})
	out := make([]record, 0, len(keys))
	for _, k := range keys {
		out = append(out, record{Key: k, Fields: byKey[k]})
	}
	return out
}

type canvasView struct {
	Name    string
	Content string
}

type buttonView struct {
	Label  string
	Action string
	Target string
}

type pageView struct {
	Title    string
	Canvases []canvasView
	Buttons  []buttonView
}

const pageHTML = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{{.Title}}</title>
<style>
body { font-family: sans-serif; margin: 2rem; background: #fafafa; color: #222; }
figure.canvas { margin: 0 0 1.5rem 0; }
figure.canvas .art { width: 480px; height: 320px; border: 1px solid #ccc; background: #fff; }
figcaption { font-size: 0.9rem; color: #666; margin-top: 0.4rem; }
.controls button { font-size: 1rem; padding: 0.5rem 1rem; margin-right: 0.5rem; }
</style>
</head>
<body>
<h1>{{.Title}}</h1>
{{range .Canvases}}<figure class="canvas" data-name="{{.Name}}">
<div class="art"></div>
<figcaption>{{.Content}}</figcaption>
</figure>
{{end}}<p class="controls">
{{range .Buttons}}<button type="button" data-action="{{.Action}}" data-target="{{.Target}}">{{.Label}}</button>
{{end}}</p>
<script src="/app.js"></script>
</body>
</html>
`

const appJS = `(function () {
  "use strict";
  function artOf(name) {
    var nodes = document.querySelectorAll("figure.canvas");
    for (var i = 0; i < nodes.length; i++) {
      if (nodes[i].getAttribute("data-name") === name) {
        return nodes[i].querySelector(".art");
      }
    }
    return null;
  }
  function rnd(a, b) {
    return a + Math.random() * (b - a);
  }
  function num(a, b) {
    return rnd(a, b).toFixed(1);
  }
  function hue() {
    return Math.floor(rnd(0, 360));
  }
  function paint(name) {
    var host = artOf(name);
    if (!host) { return; }
    var w = 480, h = 320;
    var s = '<rect width="' + w + '" height="' + h + '" fill="hsl(' + hue() + ', 55%, 94%)"/>';
    var n = 8 + Math.floor(Math.random() * 12);
    for (var i = 0; i < n; i++) {
      var fill = 'hsl(' + hue() + ', 70%, ' + Math.floor(rnd(35, 75)) + '%)';
      var kind = Math.floor(Math.random() * 3);
      if (kind === 0) {
        s += '<circle cx="' + num(0, w) + '" cy="' + num(0, h) + '" r="' + num(10, 70) + '" fill="' + fill + '" opacity="0.7"/>';
      } else if (kind === 1) {
        s += '<rect x="' + num(0, w) + '" y="' + num(0, h) + '" width="' + num(20, 160) + '" height="' + num(20, 160) + '" fill="' + fill + '" opacity="0.6"/>';
      } else {
        s += '<polyline points="' + num(0, w) + ',' + num(0, h) + ' ' + num(0, w) + ',' + num(0, h) + ' ' + num(0, w) + ',' + num(0, h) + '" fill="none" stroke="' + fill + '" stroke-width="' + num(2, 10) + '"/>';
      }
    }
    host.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ' + w + ' ' + h + '" width="100%" height="100%" preserveAspectRatio="xMidYMid slice">' + s + '</svg>';
  }
  function erase(name) {
    var host = artOf(name);
    if (host) { host.innerHTML = ""; }
  }
  function save(name) {
    var host = artOf(name);
    if (!host) { return; }
    var svg = host.querySelector("svg");
    if (!svg) { return; }
    var blob = new Blob([svg.outerHTML], { type: "image/svg+xml;charset=utf-8" });
    var url = URL.createObjectURL(blob);
    var a = document.createElement("a");
    a.href = url;
    a.download = name + ".svg";
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
  }
  var actions = { paint: paint, clear: erase, download: save };
  var buttons = document.querySelectorAll("button[data-action]");
  for (var i = 0; i < buttons.length; i++) {
    buttons[i].addEventListener("click", function (ev) {
      var b = ev.currentTarget;
      var fn = actions[b.getAttribute("data-action")];
      if (fn) { fn(b.getAttribute("data-target")); }
    });
  }
  var canvases = document.querySelectorAll("figure.canvas");
  for (var j = 0; j < canvases.length; j++) {
    paint(canvases[j].getAttribute("data-name"));
  }
})();
`

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	view := pageView{Title: "website"}
	for _, rec := range records("CANVAS") {
		view.Canvases = append(view.Canvases, canvasView{
			Name:    rec.Fields["name"],
			Content: rec.Fields["content"],
		})
	}
	for _, rec := range records("BUTTON") {
		view.Buttons = append(view.Buttons, buttonView{
			Label:  rec.Fields["label"],
			Action: rec.Fields["action"],
			Target: rec.Fields["target"],
		})
	}
	page := template.Must(template.New("page").Parse(pageHTML))
	mux := http.NewServeMux()
	mux.HandleFunc("/app.js", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/javascript; charset=utf-8")
		w.Write([]byte(appJS))
	})
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/" {
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		if err := page.Execute(w, view); err != nil {
			log.Println("render:", err)
		}
	})
	log.Println("website listening on port " + port)
	log.Fatal(http.ListenAndServe(":"+port, mux))
}