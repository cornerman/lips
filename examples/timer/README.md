<!-- Written by `lips generate`. Every mint overwrites it; edits are lost. -->

# The `timer` language

This language describes one scheduled job in three sentences.

- `run <command> every day at <hh>:<mm>.` states the command to run and the
  daily time. The time is captured as two parts (hour, minute) so each world
  can spell it in its own notation.
- `run it in the image <image>.` states the container image. Only Kubernetes
  has a place for it; on a machine it is explicitly ignored, since the script
  is run directly from the filesystem.
- `name the job <name>.` names the job.

On NixOS the job becomes a systemd service (its `ExecStart` is the command,
its description is the job name) driven by a systemd timer of the same
instance name, whose `OnCalendar` is `*-*-* HH:MM:00` and which is wanted by
`timers.target`. Nothing is built: the command is taken as a path string.

On kubenix the job becomes a `CronJob` keyed by the program's instance name,
with `spec.schedule` written as the cron expression `MM HH * * *`, one
container (also keyed by the instance name) carrying the image and the
command.

A program that omits the command or the time is asked for it in both worlds;
a program that omits the image is asked only for the kubenix rendering, which
cannot run a pod without one. Nothing here is invented: every value in the
output comes from a word in the program, except the constants `timers.target`
and the `* * *` day/month/weekday fields that make "every day" explicit.
