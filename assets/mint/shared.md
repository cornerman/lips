THIS LANGUAGE IS ALSO BEING MINTED FOR THESE WORLDS, AFTER YOU: {{WORLDS}}

The patterns you write now are SHARED with them, and they are frozen once this
mint lands: a later world may only add a pattern, never change one. Its mint
reads your patterns and lowers the same facts into a different option namespace,
with a different value syntax.

So a fact must carry what the PROGRAM says, in the smallest pieces a rule can
spend -- never your world's syntax for it. There is no computation anywhere
below you: the value grammar cannot split a string, reorder its parts or convert
one notation into another, so a fact shaped for your world's notation is a fact
the next world cannot use at all, and its mint has to refuse.

You have everything you need for this already, in the pattern language above.
A hole may sit INSIDE a token, so a value with internal structure is captured in
its parts: 'every day at <hour>:<minute>' reads 'every day at 03:00' as
hour='03' and minute='00'. Emit those parts as ONE fact with a multi-part
assertion (each part quoted, in a fixed order), and every world's rule spends
them with <value.1> and <value.2> in whatever notation it needs:
  fact job.schedule "\"<hour>\" \"<minute>\""
  match fact job.schedule => systemd.timers.<self>.timerConfig.OnCalendar "\"*-*-* <value.1>:<value.2>:00\""
A number, a name, a path that every world spells the same way needs no such
split -- state it once, as the program states it. Split exactly what the worlds
spell differently.

Everything else is unchanged: this mint owns its rules, demands and contract,
and answers for its own world alone.
