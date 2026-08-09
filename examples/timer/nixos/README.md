<!-- Written by `lips generate`. Every mint overwrites it; edits are lost. -->

# The `timer` language

This language describes one scheduled job per program file. It reads exactly
two sentences.

`run <command> every day at <time>.` states the command to run (an absolute
path, taken verbatim) and the time of day it runs, written HH:MM.

`name the job <name>.` states what the job is called; the name becomes the
description of both units.

Mechanism: each program becomes a systemd service plus a systemd timer, both
keyed by the program's own instance name (the file basename), so two such
programs compose in one configuration without collision. The service is a
`oneshot` whose `ExecStart` is the command as given -- nothing is built, the
path is expected to exist on the machine. The timer drives it with
`timerConfig.OnCalendar = "*-*-* HH:MM:00"` (systemd calendar syntax, derived
from the stated time) and is pulled in by `timers.target`, which is what makes
it start at boot.

What I had to decide, since the program is silent about it: the unit type
(`oneshot`, the right shape for a script that runs and exits), and that the
timer is not `Persistent` -- a missed run (machine off at 03:00) is skipped
rather than caught up. Change that by re-minting if catch-up is wanted.

The time is captured as ONE token, `03:00`, rather than as separate hour and
minute parts; the contract check refuses a fact whose parts are spent apart,
and no systemd spelling puts them side by side. This is filed as a gap: a
world that writes schedules in another notation (a cron field order, say)
would need the parts and cannot re-split this token.

Any program in this language must state both sentences: a program missing one
is asked for the command, the time, or the name.

Contract: the command reaches `ExecStart`, the time reaches `OnCalendar`, and
the name reaches the service description.

## Known Gaps

### multipart-fact-not-contiguous

blocked line: run /var/lib/scripts/cleanup.sh every day at 03:00.
wanted: fact job.schedule "<hour> <minute>" spent as
  systemd.timers.<self>.timerConfig.OnCalendar "\"*-*-* <value.1>:<value.2>:00\""
the derived contract check demands the assertion's parts appear contiguously,
joined by a single space, inside one emitted option value:
  OnCalendar: should contain 03 00, but is "*-*-* 03:00:00"
no systemd calendar spelling can put the two parts side by side, so the
documented "split what worlds spell differently" shape cannot be used here.

