<!-- Written by `lips generate`. Every mint overwrites it; edits are lost. -->

# The `watch` language

This language describes a small line-filtering tool and the machine that runs
it. Five sentences, in any order:

- `read a line at a time from standard input and print every line that
  contains the word WORD.` -- the behaviour. WORD is the only value here; the
  loop itself is fixed. It becomes two clauses: `contains?`, a plain substring
  search over a line, and `main`, which reads lines with `read-a-line` until
  end of input and calls `emit` on each line the search accepts. Matching is
  substring matching, so `ERROR:` and `ERRORS` both count as containing
  `ERROR`; change the word in the sentence and the built program changes with
  it.
- `install the tool as the command NAME.` -- the clauses are built into one
  executable (the site) and installed system-wide through
  `environment.systemPackages`, under the name this line gives.
- `run NAME every N minutes as a system service.` -- a `oneshot`
  systemd service whose `ExecStart` is the site's binary, plus a systemd timer
  wanted by `timers.target` that starts it one minute after boot and every N
  minutes thereafter (`OnUnitActiveSec = "Nmin"`).
- `give the service the name NAME.` -- the unit's own name: it keys
  `systemd.services.<NAME>` and also fills the unit description and the
  journal identifier, so the service is findable under exactly that word.
- `given the lines "A" and "B", print only OUT.` -- the worked example. It
  becomes a claim, checked offline on every compile: the two lines are fed to
  the program and what it printed must be exactly the one line OUT. This is
  the only thing that holds the generated code to the sentence that asked for
  it, so the language demands it.

One thing to know when editing: the command name, the name in the `run ...`
sentence and the service name are three separate words, and each one keys what
it names. Written as three different words you would get an installed command
under one name and a unit under another, so keep them the same word unless you
really mean them to differ.

Every sentence must be present: a program missing any of the five is refused
at compile time with the question the missing line answers. Nothing here is
invented -- the only values I chose without the program stating them are the
timer's one-minute start delay after boot and the `oneshot` service type,
both mechanism, not policy.

What is pinned by the contract: the unit description (from the service name),
the timer interval, and the claim's expected output. The installed command
name and the `ExecStart` path are not pinned by an expect, because they name
a build result rather than a checkable value; the rules that emit them are
the whole contract there.
