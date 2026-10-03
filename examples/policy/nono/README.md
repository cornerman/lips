<!-- Written by `lips generate`. Every mint overwrites it; edits are lost. -->

# The `policy` language

No engine lines changed. The engine you already have reads every line of `dev.policy.lips`, so this patch adds only this report.

How each line is read:

- **"the agent works in the directory it is started in and may read and write it."** (p1) sets `workdir.access` to "readwrite". It also sets `meta.name` to the program's own name, `dev`, so you run it with `nono run --profile <dir>/profile.json -- <agent>`. The other form, "... and may read it" (p2), gives "read". If a program has neither line, it is asked for one (q1).
- **"it may read A, B and C"** (p3) adds each path to `filesystem.read` (read-only).
- **"it may never read A, B or C"** (p4) adds each path to `filesystem.deny`.
- **"it may run X, Y and Z"** (p5) sets `default: "allow"` for each tool under `command_policies.commands.<tool>.from.session.invocation_policy`. It also gives each tool an empty `sandbox`, because nono's validator refuses a `from.session` entry without one.
- **"it may never run X, Y or Z"** (p6) does the same with `default: "deny"`.
- **"it must ask me before running git push"** (p7) adds `{argv: {prefix: ["push"]}}` to git's `approve` list. It also declares a `terminal` approval backend and makes it the default, so nono asks the person at the session before running the command. Without a backend, nono refuses the profile.
- **"on the network it may reach A and B, and nothing else"** (p8) adds each host to `network.allow_domain`.

Some limits you should know about:

- **Deny groups:** the language has no line for `groups.include`, so the profile switches on none of nono's built-in deny groups. The only deny rules are the paths you list after "it may never read". To use nono's built-in groups, a new line shape is needed, which means a new mint.
- **Asking before a command:** p7 reads only one subcommand word (`git push`, not `git push --force`).
- **Old command section:** nothing is written to the deprecated `commands.allow`/`commands.deny` section.
