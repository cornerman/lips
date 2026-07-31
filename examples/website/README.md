<!-- Written by `lips generate`. Every mint overwrites it; edits are lost. -->

# The `website` language

## What this language says

A program describes one small website with one drawing surface and one
button, in four kinds of line:

```
website running on port 8081
canvas "main":
  content: shows a nice random svg painting
button "drück mich":
  on click: new random painting in canvas "main"
```

* `website running on port <port>` — the TCP port the site listens on.
* `canvas "<name>":` — opens a canvas block; the quoted name becomes the
  element id of the drawing surface in the page.
* `content: <words...>` — a line inside a canvas block; the words become the
  caption shown under the surface and its accessible label.
* `button "<label>":` — opens a button block; the quoted label is the text
  printed on the button (spaces and umlauts are fine, it is quoted).
* `on click: <action words...> in canvas "<name>"` — a line inside a button
  block. The action phrase becomes the button's tooltip; the quoted canvas
  name is the surface the click actually repaints, so it must be stated.

Every quoted or numeric word above is a hole: edit the sentence, recompile,
and the machine follows. Nothing in the engine hard-codes 8081, "main" or
"drück mich".

## What it builds

The mechanism is one systemd service per program, keyed by the program's own
file name (`website.lips` → `systemd.services.website`), running a tiny Go
HTTP server built from source as an artifact (`buildGoModule`, no external
dependencies, binary `bin/site`). The service runs under `DynamicUser`, wants
`multi-user.target`, restarts on failure, and the stated port is opened in
`networking.firewall.allowedTCPPorts`.

All five program values reach the server through the unit's environment —
`PORT`, `CANVAS_ID`, `CANVAS_CAPTION`, `BUTTON_LABEL`, `BUTTON_ACTION`,
`BUTTON_TARGET` — and the server renders the page from them at request time.
That is deliberate: environment values are plain strings in the NixOS option
tree, so each one is pinned by an expect in `website.expect`, and no value is
baked into the compiled binary (there are no source fills at all). The Go
source holds only *structure*: the HTML skeleton and the JavaScript that
generates a random SVG painting (circles, rectangles, lines in random
colours) into the element named by `CANVAS_ID` and regenerates it whenever
the button is clicked.

## What I had to decide, and the limits

* "shows a nice random svg painting" and "new random painting" are prose. A
  lips engine cannot synthesise behaviour from prose, so the *behaviour* is
  the fixed mechanism I wrote (random SVG shapes, redrawn on click) and the
  prose itself is carried into the page as the caption and the button
  tooltip, where a human can see the sentence they wrote. If you want a
  different kind of painting, that is a regeneration, not an edit.
* The click line must end with `in canvas "<name>"`. Without a named target
  the engine would have to guess which surface to repaint, and guessing is
  what I am forbidden to do; a missing on-click line is asked for instead
  (see the demands below).
* Exactly **one** canvas and **one** button per program. Their facts live at
  fixed subjects (`canvas.name`, `button.label`, ...), so a second `canvas
  "…":` block would be refused at compile time as a conflict. Supporting
  several would mean repeating a block of page structure per widget, which
  the source-fill mechanism cannot do; that is a regeneration with a
  different design, not something to fake here.
* Version `0.1.0` for the build and the page geometry (640x400) are free
  constants I chose; nothing in the program pins them.

## What a program must state

A program is asked (at compile time, by name) for anything it leaves silent:
the port, the canvas name and its content line, the button label, and the
click action with its target canvas. All six are things a human can simply
write in one line, so none of them has an invented default.
