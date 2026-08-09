<!-- Written by `lips generate`. Every mint overwrites it; edits are lost. -->

# The `website` language

## What this language describes

A one-page canvas website: a port, one or more drawing areas ("canvases"),
and buttons that act on a named canvas. Every program becomes one systemd
service on this machine, named after the program file (`website.lips` ->
`systemd.services.website`), plus the port opened in the firewall.

## The line shapes it accepts

- `website running on port <port>` — the tcp port the site is served on.
  This is the one line every program must have; a program without it is
  asked for it.
- `canvas "<name>":` — opens a canvas block. The name identifies the canvas
  and is what buttons refer to.
  - `content: shows <phrase>` — the canvas description, shown as the
    caption under the drawing area.
- `button "<label>":` — opens a button block; the label is the button text.
  - exactly one of these three click lines, written as-is apart from the
    canvas name:
    - `on click: new random painting in canvas "<name>"`
    - `on click: erase everything in canvas "<name>"`
    - `on click: download the picture from canvas "<name>"`

Everything in `<angle brackets>` is a value you can edit freely (port,
names, labels, the content phrase). Everything else is a fixed word: the
three click sentences *select* a behaviour, so they are literal wording, not
prose. Reword one of them and the build fails loudly rather than silently
dropping a button's behaviour; that is when you need a new engine.

Blocks are read by the heading line, not by indentation, so indenting the
`content:` / `on click:` lines is optional but recommended. Canvases and
buttons are keyed by their position in the program, which is why two buttons
may carry the same label or target the same canvas without colliding, and
why they appear on the page in the order you wrote them.

## The mechanism I chose

There is no off-the-shelf NixOS service for "a page with a canvas and three
buttons", so the site is a small Go http server built from source
(`buildGoModule`, sources in `artifacts/website/`). The server is generic:
it renders the page from what it finds in its own environment, and the
module puts the program's words there:

- `PORT` — the port from the first line (also added to
  `networking.firewall.allowedTCPPorts`).
- `CANVAS_<n>_NAME`, `CANVAS_<n>_CONTENT` — one pair per canvas.
- `BUTTON_<n>_LABEL`, `BUTTON_<n>_ACTION`, `BUTTON_<n>_TARGET` — one triple
  per button, where the action is the normalised word `paint`, `clear` or
  `download` chosen by which click sentence you wrote.

So editing a label or a port changes only the unit's environment; nothing
is rebuilt. The unit runs with `DynamicUser` and restarts always.

The drawing itself happens in the browser (`/app.js`, served by the same
binary): `paint` generates a random svg picture into the target canvas,
`clear` empties it, `download` saves the current svg as `<canvas>.svg`.
Every canvas is painted once on page load, which is what "shows a nice
random svg painting" means here.

## What I had to decide myself

- **The renderer is fixed.** This language has exactly one kind of picture:
  a randomly generated svg painting. The `content:` phrase is therefore
  carried to the page as the canvas *caption* (the visible description),
  not as an instruction to some other renderer. If you write
  `content: shows a bar chart` you will get a random painting captioned
  "a bar chart" — say so in the report of the next mint if you need real
  renderer choice, that needs new patterns.
- **Firewall.** The program says the site runs on a port, so the port is
  opened. Remove that emit in a regeneration if the machine is behind a
  reverse proxy.
- **Build inputs.** Version `0.1.0` and `vendorHash = null` (the server has
  no Go dependencies) are my choices; nothing in the program pins them.
- **The binary is called `website`.** The build is a fixed mechanism named
  `website`, while the systemd unit is named after your program file, so
  renaming `website.lips` renames the service but keeps the same server
  binary.
