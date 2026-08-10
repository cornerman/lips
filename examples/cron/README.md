<!-- Written by `lips generate`. Every mint overwrites it; edits are lost. -->

# The `cron` language

This language describes one scheduled container run per program. The program's
file name is the instance name, so two such programs compose without collision.

Lines it reads:

- `run the image <image> every night at <hh>:<mm>.` -- the image to run and the
  time of day. The time is captured as two parts (hour, minute), because the two
  worlds spell a schedule differently and nothing below may rewrite a value.
- `the command is <command>.` -- the whole command line the image runs.
- `keep <n> finished runs in the history.`
- `give up on a run after <n> seconds.`

**kubenix.** The program becomes a CronJob named after the instance: the time
becomes `spec.schedule` (`30 02 * * *`), the retention becomes
`successfulJobsHistoryLimit` and `failedJobsHistoryLimit`, the give-up time
becomes the job template's `activeDeadlineSeconds`, and image and command become
the single container of the job's pod, whose `restartPolicy` is `OnFailure`
(a job pod must not restart forever; that is a mechanism choice, not a value).

**NixOS.** The program becomes an oci-container (podman backend) that does not
autostart, plus a systemd timer `podman-<instance>` whose `OnCalendar` is
`*-*-* 02:30:00`; that timer starts the container's own unit
`podman-<instance>.service`, on which the give-up time becomes `RuntimeMaxSec`.

The command is handed over as `/bin/sh -c "<command>"` in both worlds, so one
sentence carries a command line with any number of arguments and the two worlds
stay identical. An image without a shell would need a different mechanism.

What NixOS cannot honor: keeping a number of finished runs. systemd has no such
retention setting, so there the count is only recorded as a container label
(`labels.history`) -- low confidence, and filed as a gap. On Kubernetes it is
honored for real.

Any program in this language must state the image, the command and the time;
those three are demanded in both worlds. Retention and the give-up time are
optional -- leave the line out and each world keeps its own default.

## Known Gaps

### nixos-run-history

blocked line: keep 3 finished runs in the history.
NixOS/systemd has no option for retaining a number of finished runs; the count
can only be recorded as metadata (a container label), never enforced.

