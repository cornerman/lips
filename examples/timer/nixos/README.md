<!-- Written by `lips generate`. Every mint overwrites it; edits are lost. -->

# The `timer` language

This language describes one scheduled job per program, in two sentences.

**Line shapes it accepts**

- `run <command> every day at <HH:MM>.` — the command is a path (or any
  single token) that will be executed, and the time is the daily wall-clock
  time it runs at. Both are holes: edit either word and recompile, and the
  machine follows.
- `name the job <name>.` — a single word naming the job.

**Mechanism**

Each program becomes a systemd service plus a systemd timer, both keyed by
the program's own instance name (`nightly.timer.lips` → `systemd.services.nightly`
and `systemd.timers.nightly`), so two such programs compose in one
configuration without colliding, and the timer drives the service of the
same name.

- the command goes to `serviceConfig.ExecStart`, and the unit is
  `Type = "oneshot"` — the right shape for a job that runs, finishes and
  exits rather than staying resident.
- the time becomes systemd calendar syntax in
  `timers.<self>.timerConfig.OnCalendar`: `03:00` is written out as
  `*-*-* 03:00:00`, i.e. every day at that hour and minute. The timer is
  pulled in by `timers.target` so it is actually active after a rebuild.
  Only the daily form is read; a weekly or hourly sentence would be a new
  line shape and needs a fresh mint.
- the job name is carried into the `Description` of both units and into
  `SyslogIdentifier` on the service, so `systemctl status` and the journal
  show the human's word for the job. I deliberately did **not** rename the
  unit files after it: the unit names come from the program's filename, and
  making them follow a sentence would silently change the names an operator
  and other units already refer to.

**What I had to decide myself**

`Type = "oneshot"` and the `timers.target` wiring are mechanism constants —
the programs never mention them and no reasonable program would. The
schedule is kept as the program's own `HH:MM` text in the decision
`job.schedule`, and the systemd calendar expression is assembled in the
rule, not in the program.

**Contract**

Three checks are pinned on every future compile: the command reaches
`ExecStart`, the stated time appears in `OnCalendar`, and the job name
appears in the service `Description`.
