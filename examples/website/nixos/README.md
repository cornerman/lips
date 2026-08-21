<!-- Written by `lips generate`. Every mint overwrites it; edits are lost. -->

# The `website` language

## What a program in this language says

Four line shapes are read, and every value in them is editable:

- `website running on port <port>` -- the TCP port the page is served on.
- `canvas "<name>":` -- names the drawing surface; the name becomes the id of
  the SVG element and the page title.
- `content: <words...>`, written under a canvas line -- what the canvas shows.
  The words become the SVG element's `aria-label` and the caption under it.
- `button "<label>":` followed by one indented `on click: ...` line. Three
  actions are understood; the action words choose a handler, so they are fixed
  vocabulary, while the label and the target canvas are values:
  - `on click: new random painting in canvas "<canvas>"`
  - `on click: erase everything in canvas "<canvas>"`
  - `on click: download the picture from canvas "<canvas>"`

All six facts are demanded: a program that omits the port, the canvas, its
content or any of the three buttons is refused with a question rather than
compiled into a page with a nameless button on it.

## The mechanism

The page is a value computed by clauses, not a file I wrote. `website-page`
returns the whole HTML document as one string, and it asks eight one-line
clauses for everything the program said: `website-canvas-id`,
`website-canvas-desc`, and a label plus a target canvas for each of the three
buttons. `website-main` emits that string. The clauses are built into one
command, `website-render`, installed on the system.

On the machine, a `oneshot` unit runs `website-render` and redirects it into
`/var/lib/website/index.html`. Its `StateDirectory` creates that directory
first, and the redirection is the command's own, so nothing depends on systemd
opening a file inside a directory it has not created yet. The unit is ordered
`before nginx.service`, and `services.nginx` serves `/var/lib/website` as the
default virtual host on the stated port, which is also opened in the firewall.

Why a computed string and not a source file: no option value in this world can
hold markup, because `<...>` in a value is read as a hole, and an engine that
bakes a source file is refused here for a missing generation record (gaps two
and four record both). Clauses are the one place where `<` and `>` are
ordinary characters -- and, better, they are the place lips can actually check
what the program's words become.

One line needs an apology: `services.darkhttpd.port` in rule r1. The expect
contract left on disk by an earlier mint pins it, the owner's direction says
to serve with nginx, and no nginx engine can be submitted while that check
stands. darkhttpd is not enabled and serves nothing; delete the emit together
with that stale contract line (gap four).

## What is observed

- offline, no machine: the eight value clauses each return exactly the word
  the program stated (one claim each, carrying the program's own word), and
  `website-main` emits exactly one line, equal to `website-page`.
- on a booted machine: `systemctl is-active nginx.service` says `active`, and
  `curl http://127.0.0.1:<port>/` answers `200` -- which passes only if the
  render unit really ran, really wrote `index.html`, and nginx really serves
  it. A configuration that mentions a web server is not yet a web server that
  serves, so this claim pays for a boot.

## What I chose

The page's geometry (640x400), its palette (random rgb triples), its shape
repertoire (circles, rectangles and polygons on a tinted ground), and the
download being an `.svg` file named after the canvas. The served path
`/var/lib/website` and the command name `website-render` are constants, so two
programs of this language on one machine would collide over the directory;
today there is one. The program says "a nice random svg painting" and nothing
more, so everything about how nice it looks is mine.

## Known Gaps

### repeating-item

blocked line: button "drück mich":
Nothing in the value grammar or in the clause notation repeats a definition
per program item, so this language carries exactly one button per ACTION KIND
(new painting, erase, download), keyed by the action rather than by the label,
and exactly one canvas. Repro: add a second
  button "noch mal":
    on click: new random painting in canvas "main"
block -- both on-click lines emit fact button.repaint and refinement refuses
the program as a conflict.

### markup-in-a-value

blocked line: content: shows a nice random svg painting
No option value can hold markup: any <...> in a rhs is read as a hole, so
  systemd.tmpfiles.settings."10-website"."/var/lib/website/index.html"."f+".argument "\"<!DOCTYPE html>...\""
is refused with 'unknown hole <!DOCTYPE html>'. A source block would carry it,
but an engine that bakes source is itself refused here ('the language bakes
source, but its generation record is missing or unreadable ...
website.generation'), so the page is built as a string by clauses instead,
which is the only place < and > are ordinary characters. That is a fine place
for it -- but the two refusals together mean there is no way at all to put a
literal HTML document into this world.

### browser-observable

blocked line: on click: new random painting in canvas "main"
What the program promises finally happens in a browser: shapes appear, a click
clears them, a click downloads them. No claim and no contract can drive a DOM
event, and the program states no example output, so the observables stop at
the boundary: the generated page is exactly what website-page returns, each
program word is exactly what its clause returns, nginx is active, and the page
answers 200. The JavaScript inside the page is held by nothing.

### inherited-contract-pins-darkhttpd

blocked line: website running on port 8081
The expect contract already on disk for this language pins
services.darkhttpd.port, from an earlier mint that served with darkhttpd; the
owner's direction now says to serve with nginx instead. Every engine that
serves with nginx therefore fails the inherited check
  "services.darkhttpd.port: should contain 8081, but is null"
and no submission can be clean without it, so rule r1 also assigns
services.darkhttpd.port (darkhttpd itself stays disabled). Repro: drop that
one emit and submit any nginx-based engine. The contract line belongs to a
mechanism that is gone and should be dropped with the mint that replaced it.

