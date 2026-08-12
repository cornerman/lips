<!-- Written by `lips generate`. Every mint overwrites it; edits are lost. -->

# The `website` language

This language describes a tiny single-page website, and the machine both
generates the page and serves it.

Line shapes it accepts:

- `website running on port <port>` -- the port the site is served on. This is
  the one line the language demands; a program that omits it is asked for it.
- `canvas "<name>":` -- a drawing area. The quoted name becomes the element id
  in the page and is how a button refers to it.
- `content: shows a nice random svg painting` (written under a canvas) -- what
  that canvas shows. This wording is FIXED: it selects a mechanism (a random
  SVG painting), it is not a free description.
- `button "<label>":` -- a button; the quoted label is the text on it.
- `on click: new random painting in canvas "<target>"`,
  `on click: erase everything in canvas "<target>"`,
  `on click: download the picture from canvas "<target>"` (each written under a
  button) -- the three recognised click actions. The verbs are fixed wording
  (they choose behaviour); the quoted canvas name is a value.

How it is realized. Each canvas, content, button and click line contributes one
piece of the page to a single behaviour clause, `main`, which PRINTS the page:
a canvas line prints its `div` plus the painting, erasing and downloading
helpers; a content line prints the script that paints that canvas (matched by
the line's position, carried in `data-slot`); a button line prints its
`button`; a click line prints the script that wires that button's `onclick` to
the named canvas. Because the pieces are contributions to one clause, adding a
canvas or a button is just more lines -- no count is baked anywhere.

The machine runs that program once at boot as a oneshot unit named after the
program, redirects its output to `/var/lib/<program>/index.html`
(`StateDirectory` creates the directory), and serves that directory with
`darkhttpd` on the stated port. `<self>` is the program's own name throughout,
so two such programs never collide.

What I chose, and what I could not do. The server (darkhttpd -- the smallest
static server in the option tree), the document root, the oneshot-generates-
the-page arrangement, and the JavaScript that draws random circles are
mechanism choices, not values from the program. Three things are filed as gaps.
First, a rule value cannot contain markup at all: `<div>` in a Nix value is
read as a hole, so the page had to be routed through clause strings. Second, no
contract reaches a document, an element or a click, so the in-page behaviour
cannot be expressed as clauses lips can check -- the clauses only print the
JavaScript that performs it. Third, the program states no example of what the
page shows, so the claim over `main` is only a smoke test that it runs; one
sentence naming an expected line would give a real witness, and I did not
invent one. The expect pins the stated port to the option that carries it; the
remaining values (canvas name, content kind, labels, actions) reach the page
text through the clause, which no expect can address.

## Known Gaps

### no-stated-observable

blocked line: content: shows a nice random svg painting
the program states no example of what the page must show, so the only claim
possible over the generated page is a smoke claim: (begin (main) #t). a
sentence like 'the page starts with <meta charset=utf-8>' or 'clicking
"leeren" empties the canvas' would give a real witness.

### angle-brackets-in-values

blocked line: content: shows a nice random svg painting
a rule value cannot contain markup: emitting
  environment.etc.page.text "\"<div id=page></div>\""
is refused with 'unknown hole <div id=page>', because <...> in a nix value is
read as a hole. html therefore has to be routed through clause strings (where
the hole marker is #<...>), even where a plain file would do.

### browser-behaviour

blocked line: on click: new random painting in canvas "main"
no contract reaches a document, an element or a click, so in-page behaviour
cannot be written as clauses that lips can check; the clauses here only PRINT
the javascript that does it, and that javascript is checked by nothing.

