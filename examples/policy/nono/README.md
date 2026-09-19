<!-- Written by `lips generate`. Every mint overwrites it; edits are lost. -->

# The `policy` language

This language writes a nono sandbox profile from plain sentences about what an
agent may touch.

Line shapes it accepts:

- `the agent works in the directory it is started in and may read and write it.`
  (or `... and may read it.`) -- sets `workdir.access` to `readwrite` or `read`.
  Every profile must say this; a program that is silent is asked for it.
- `it may read A, B and C.` -- each path becomes an element of `filesystem.read`.
- `it may never read A, B or C.` -- each path becomes an element of
  `filesystem.deny`.
- `it may run git, rg, ls and cat.` -- each name becomes
  `command_policies.commands.<tool>.from.session` with `invocation_policy.default
  = "allow"`.
- `it may never run curl, wget or ssh.` -- the same slot with default `"deny"`.
- `it must ask me before running git push.` -- an `approve` entry matching the
  argv prefix (`{ argv = { prefix = [ "push" ] }; }`) on that tool, plus a
  `terminal` approval backend named as the approval default, because nono
  refuses an approve entry with no backend. One subcommand word is read; a
  longer argv prefix has no form in this language yet.
- `on the network it may reach github.com and crates.io, and nothing else.` --
  each host becomes an element of `network.allow_domain`. The closing "and
  nothing else" is fixed wording: allow-listing is already exclusive in nono.

All list sentences are read with list holes, so they take any number of items;
there is no pattern per item count.

Mechanism notes and things I had to decide:

- Permission lives where nono enforces it against child processes:
  `filesystem.*`, `workdir.access`, `network.allow_domain`, and
  `command_policies.commands.*`. The deprecated `commands.allow/deny` section is
  never emitted.
- The schema lookup could not read this world at mint time, so the paths below
  `command_policies.commands.<tool>.from.session` come from the profile guide
  alone. Each command entry carries a sandbox object (written as an empty
  `sandbox.fs_read` list) beside its invocation policy, because an entry holding
  only an invocation policy is rejected by nono's validator.
- A command you want to gate with "ask me first" should also appear in an
  `it may run ...` sentence: the sandbox object for that tool comes from the
  run/never-run sentence, not from the approval sentence.
- `meta.name` is the program's own instance name.
- Subject vocabulary follows the previous engine: `workdir.access`, `fs.read.<n>`,
  `fs.deny.<n>`, `cmd.<tool>.policy`, `cmd.<tool>.approve`, `net.allow.<n>`.
  Paths and domains are keyed by their position in their sentence, so state all
  read paths in one sentence and all denied paths in one sentence; two separate
  `it may read ...` lines would collide on position 1.
- No `groups.include` is emitted: the programs name no deny group, and inventing
  one would silently add rules nobody asked for. Denials are exactly the paths
  and commands the program names.

The contract pins every value the sentences carry -- workdir access mode, each
read path, each denied path, each command's default decision, each allowed
domain. The approve entry is not expected, because its value is a record the
expect grammar compares poorly; the rule that emits it is its whole contract.
