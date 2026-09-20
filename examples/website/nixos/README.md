<!-- Written by `lips generate`. Every mint overwrites it; edits are lost. -->

# The `website` language

## What this language says

A program describes one small web page and the port it is served on:

```
website running on port 8081
canvas "main":
  content: shows a nice random svg painting
button "drück mich":
  on click: new random painting in canvas "main"
```

Five line shapes, and nothing else:

- `website running on port <port>` -- the first line; it opens the page and
  fixes the port. Every other line is read as belonging to it.
- `canvas "<name>":` -- a drawing surface, named. Repeatable.
- `content: <what it shows>` -- written under a canvas; its caption.
- `button "<label>":` -- a button, labelled. Repeatable.
- `on click: <what happens>` -- written under a button; the action sentence.
  The canvas it names in quotes is the one that button acts on.

Canvases and buttons are numbered by their position in the program, so two
buttons may share a label, and a label may contain spaces (`"drück mich"`).

## The mechanism

**nginx serves it.** `services.nginx.defaultHTTPListenPort` is the program's
port, the port is opened in the firewall, and the virtual host -- keyed by
the program's own instance name -- is the default server for that port, so
`curl localhost:8081` reaches it. The nginx module writes its own config;
no listen address is hand-written.

**The page itself is a clause.** `website-page-text` holds the whole page --
markup, style and the browser script inline -- and `website-main` prints it.
It carries no program value: markup cannot pass through a NixOS option value
at all (every `<...>` there is read as a hole), so a clause string is where
it can live. Two claims observe that program offline: it prints exactly one
document, and that document is an HTML doctype.

**The document root is laid out at boot.** A oneshot unit, ordered before
nginx, creates `/var/lib/<instance>-www`, copies the data files described
below into `data/`, and redirects the printed page into `index.html` -- the
unit's own command writes the file, which is the only shape of this that
starts reliably.

**Every program value becomes a tiny file.** `environment.etc` writes
`<instance>/canvas/1/name`, `canvas/1/content`, `button/2/label`,
`button/2/action`, one value per file; the boot unit copies them under the
document root as `/data/...`. The page script fetches `data/canvas/1/...`,
`data/canvas/2/...`, `data/button/1/...` until one is missing, and builds the
canvases and the buttons out of what it finds.

That indirection is deliberate. If the buttons were written into the page
text, their number would be frozen at three -- nothing in lips repeats a
block of text per item, so a fourth button would have cost a fresh mint.
Reading them at runtime means a human adds a button, or a second canvas, by
writing two more lines and recompiling.

The script paints the picture (circles, rectangles and triangles in random
hues on an SVG surface, painted once on load), and decides what a click does
by reading that button's own action sentence: *erase/clear/leeren* wipes the
canvas, *download/save/speichern* downloads it as an `.svg` file, anything
else paints a new picture. The canvas named in quotes in the sentence is the
one acted on.

## What is checked

Expects pin every program value to the file that carries it: the port to
`services.nginx.defaultHTTPListenPort`, and each canvas name, canvas
content, button label and button action to its `environment.etc.*.text`.
Two offline claims observe the generated page. One claim boots the machine
and runs `curl -w '%{http_code}' http://localhost:<port>/`, expecting `200`
-- option values alone would never show that the layout unit ran and that
nginx really serves that root.

## What I invented, and what is missing

- The look of the page and the shape of the random painting are mine; the
  program says only "a nice random svg painting".
- Click behaviour is keyword-matched inside the page script. This is the
  filed gap `browser-behaviour`: no contract reaches a browser DOM, so the
  sentence cannot become a checked clause, and an action word outside the
  three families above silently repaints.
- One sharp edge: the `/etc` entries that carry the values are keyed
  `website-canvas-1-name` and so on, with a fixed `website-` prefix rather
  than the instance name, because a check may only name captures its subject
  binds -- the instance name is not one of them. The files themselves do land
  under `/etc/<instance>/`, so two programs of this language on one machine
  serve different documents, but they would collide on those `/etc` keys and
  the build would say so loudly.
- A program that omits the port, a canvas's `content:` or a button's
  `on click:` is asked for it rather than given a default.

## Known Gaps

### browser-behaviour

blocked line: on click: new random painting in canvas "main"
A click handler runs in a browser and touches the DOM. No contract reaches a
document, so the behaviour cannot be written as checked clauses; the page
script is a fixed string a clause prints, and it keyword-matches each
button's action sentence at runtime (erase/clear/leeren -> wipe,
download/save/speichern -> save, anything else -> repaint). An author who
invents a fourth kind of action silently gets a repaint, and no gate sees it.

Second, smaller repro -- markup cannot travel through an option value at all:
  match fact page.shell => environment.etc.page.text "\"<p id='x'>hi</p>\""
is refused with "unknown hole <p id='x'>", because every <...> in a value is
read as a hole. A source block would be the documented way out, but baking
source is itself refused here ("the language bakes source, but its generation
record is missing or unreadable"), so the markup had to be smuggled into a
clause string, where <...> is ordinary text. Either of those two holes being
closed would make this language much plainer.

