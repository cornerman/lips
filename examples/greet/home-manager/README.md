<!-- Written by `lips generate`. Every mint overwrites it; edits are lost. -->

# The `greet` language

This language installs one or more shell commands, each named and each
printing a fixed message: `install a command <name> that prints <msg>.`
builds a tiny `writeShellApplication` derivation (its text is `echo` of the
message) and adds it to `home.packages`, so the command is on the user's
PATH under its own name.

New in this mint: `run <name> every day at <time>.` schedules a command
that was installed earlier in the same program. It creates a matching
systemd user service (whose ExecStart runs the built command) and a
systemd user timer keyed by the same name, with `Timer.OnCalendar` set from
the stated time (read as HH:MM and written as a daily calendar spec,
seconds fixed at :00) and `Install.WantedBy = [ "timers.target" ]` so the
timer is actually enabled. The command name ties the schedule line back to
the command it runs -- it is a capture, not a fresh instance, so scheduling
a name the program never installed would leave ExecStart pointing at a
build that does not exist; that risk is on the author, since lips has no
way to check across two pattern families that a capture used by one was
also produced by the other.

I relied on `Timer.OnCalendar` and `Install.WantedBy`, which home-manager's
schema reports as free-form (unchecked) fields under `systemd.user.timers`;
this is the standard systemd unit vocabulary and the same shape home-manager
documentation itself uses for timers, so I kept confidence at 0.9 rather
than 1.0 to flag that the schema could not confirm the exact field names.
