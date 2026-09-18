<!-- Written by `lips generate`. Every mint overwrites it; edits are lost. -->

# The `policy` language

This patch changes two rules of the existing policy language; every line shape
the language already read is unchanged, and no new sentence is needed.

What changed and why:

- `r5` (the rule behind "it may run X" / "it may never run X" / "it must ask me
  before running X") now also emits an empty `sandbox` object for the command's
  `from.session` entry. nono's validator refuses a `from.<caller>` entry that
  carries only an `invocation_policy` ("data did not match any variant of
  untagged enum CommandFromConfig"), so without this the rendered profile for
  `dev.policy.lips` would not validate at all. The sandbox is left empty: the
  programs say nothing about giving a tool its own narrower filesystem or
  network view, so nothing is invented there.

- `r1` (the rule behind "the agent works in the directory it is started in ...",
  the one line every program must state) now also declares the approval backend:
  `command_policies.approval_backends.terminal.type = "terminal"` and
  `command_policies.approval_defaults.backend = "terminal"`. An `approve` entry
  without a declared backend is refused with `missing_approval_backend`, and
  "terminal" is the backend that asks the human sitting at the session, which is
  exactly what "it must ask me" means. It is attached to the workdir rule, not to
  the approve rule, because that line appears exactly once in every program (it
  is the one demanded line), so the declaration is emitted exactly once no matter
  how many commands need approval -- two rules writing one option path would be a
  conflict.

One limit worth knowing, unchanged by this patch: the sandbox object is emitted
by the *policy* rule, so a command that is only ever named by "it must ask me
before running <cmd> <sub>" and never by an "it may run <cmd>" line gets an
approve entry with no sandbox. In practice a program states both, as
`dev.policy.lips` does ("it may run git, rg, ls and cat." plus "it must ask me
before running git push."). If you want approval for a subcommand, also name the
command in an "it may run" line.
