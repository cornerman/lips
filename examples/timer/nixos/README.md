<!-- Written by `lips generate`. Every mint overwrites it; edits are lost. -->

# The `timer` language

This language describes one scheduled job per program file.

Two line shapes are accepted:

- `run <command> every day at <HH:MM>.` — the command to run and the time of
  day it runs. The command is taken verbatim as a path string; the time is
  turned into the systemd calendar expression `*-*-* HH:MM:00`.
- `name the job <name>.` — a human-readable name, used as the description of
  both units.

Mechanism: each program becomes a systemd service plus a systemd timer, both
named after the program's own instance name (the file's basename), so several
job programs compose in one machine without colliding. The service is
`Type=oneshot` with the stated command as `ExecStart`; the timer carries
`OnCalendar` and is pulled in by `timers.target`. Nothing is built from
source — the command is given as a path that must already exist on the
machine.

The daily shape is fixed by the wording `every day at <time>`; a program that
needs another cadence (hourly, weekly) has no line shape for it yet and would
need a fresh mint.
