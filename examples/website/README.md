<!-- Written by `lips generate`. Every mint overwrites it; edits are lost. -->

# The `website` language

## What this language describes

A `.lips` program in this language describes one small generated-art
website: the port it listens on, one **canvas** that shows a randomly
generated SVG painting, and one **button** that asks for a new painting.

Recognized lines:

- `website running on port <port>` -- the TCP port the site listens on.
- `canvas "<name>":` -- opens the (single) canvas block; `<name>` is used
  as the DOM id of the element the painting is drawn into.
- `content: shows a nice random svg painting` (nested under the canvas
  line) -- decorative: it states *what* the canvas shows, but since the
  wording never varies across an example, there is no value here to carry
  through; it is realized as a `concept`, not a fact.
- `button "<label>":` -- opens the (single) button block; `<label>` is the
  text printed on the button.
- `on click: new random painting in canvas "<target>"` (nested under the
  button line) -- `<target>` names which canvas this button refreshes.

## Mechanism

The whole site is one program built from source (there is no existing
package that generates and serves random SVGs the way this program wants),
so it becomes a Go artifact (`buildGoModule`, no external dependencies, so
`vendorHash` is `null`) wired to a `systemd.services.<self>` unit whose
`ExecStart` runs the built binary; the port is opened in
`networking.firewall.allowedTCPPorts` and handed to the binary as the
`PORT` environment variable (read at start-up, not baked in, so editing
the port needs no rebuild of the source, only a re-realized module).

The canvas id, the button's label, and the canvas name the button
refreshes are program *values*, so they reach the Go source through fills
(`@canvas_name@`, `@button_label@`, `@button_target@` in `main.go`); the
module name (`@module_name@` in `go.mod`, also used as the page title) is
filled from `<self>`, the program's own instance name, since the program
never names the website itself -- only its canvas and its button.

The server itself: `/` renders a page with the canvas div (pre-filled with
one random SVG so it has content on first load) and the button; `/random`
returns a freshly generated SVG (a handful of random colored circles) that
the button's script fetches and drops into the target element.

## Choices made without a stated value

- The build is Go with no third-party packages, so no package-manager
  choice was left underspecified.
- `version = "0.1.0"` and `Restart = "on-failure"` are fixed constants; no
  line states a version or a restart policy, and none seems worth asking
  for.
- The default port fallback (`8080`) inside the binary only matters if
  `PORT` is unset, which the module never lets happen (the rule always
  sets it from the program's stated port).

## Limitation

Only one canvas and one button are supported (see the filed gap): the
subject `canvas.name`/`button.label`/`button.target` has no per-item key,
and the generated page has no repeating block a second canvas or button
could reuse. A program stating two differently-named canvases or buttons
will fail to crystallize with a conflict, which is the intended, loud
failure rather than silently building only one.

## Known Gaps

### repeating-canvas-button

blocked shape: a program with MORE THAN ONE `canvas "X":` or `button "Y":`
block, e.g.

  canvas "main":
    content: shows a nice random svg painting
  canvas "preview":
    content: shows a nice random svg painting
  button "drück mich":
    on click: new random painting in canvas "main"

Two canvas headings with DIFFERENT names would try to write two different
values into the single subject `canvas.name` (there is no capture keying
it per-name), which lips refuses as a conflict. Keying the subject by name
instead (canvas.<name>...) would let both crystallize, but the built page
has exactly one <div> and one <script> block in source -- there is no fill
that repeats a block of HTML/JS per canvas or per button, only markers that
substitute text once. Rendering N canvases and M buttons needs a loop or
repeated markup in main.go, which is a gap in the value grammar (no
constructor for repetition), not something a rule can express. This engine
therefore only supports exactly one canvas and one button per website
program, matching the example shown.

