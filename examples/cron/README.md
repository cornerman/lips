<!-- Written by `lips generate`. Every mint overwrites it; edits are lost. -->

# The `cron` language

This language describes ONE nightly batch job per program, and renders it as a
Kubernetes **CronJob** named after the program's instance name (`report.cron.lips`
becomes `kubernetes.resources.cronJobs.report`). Nothing is installed on any
machine; the output is a manifest.

## Line shapes it accepts

- `run the image <image> every night at <hh>:<mm>.`
  Two facts in one sentence: the container image (a plain string, e.g.
  `ghcr.io/acme/report:2.3`) and the time of day. The time is read as two
  numbers around the colon, because a cron expression has to be assembled from
  them: `02:30` becomes the schedule `30 02 * * *` (every day, that minute and
  hour). There is no arithmetic in the engine, so only this "every night at
  hh:mm" shape is supported — a weekly or hourly wording would need a new mint.
- `the command is <command...>`
  Everything after "is" is the command line. Since a rule cannot split a string
  into a list, the command is handed to a shell: the container runs
  `["/bin/sh" "-c" "<your command line>"]`. That is the only way one sentence
  with an unknown number of words can become a container `command`; it does
  require the image to contain `/bin/sh`. Write the command exactly as you would
  type it in a shell.
- `keep <n> finished runs in the history.`
  Sets both `successfulJobsHistoryLimit` and `failedJobsHistoryLimit` to that
  number — "finished" covers both outcomes, so one number governs both slots.
- `give up on a run after <n> seconds.`
  Sets the Job's `activeDeadlineSeconds`, i.e. Kubernetes kills a run that is
  still going after that long.

## Mechanisms chosen (not read from the program)

- The pod's `restartPolicy` is fixed to `OnFailure`. Kubernetes refuses a Job
  pod with the default `Always`, and there is nothing for a human to decide
  here, so it is a constant of the template rather than a hole.
- The single container is keyed by the program's instance name, so the container
  is named like the job and two programs never collide.
- `concurrencyPolicy`, namespace and labels are left alone: the programs say
  nothing about them, so the Kubernetes/kubenix defaults stand. If you need a
  namespace or overlap policy, that is a new line shape and a new mint.

## What a program must state

The image and the nightly time are demanded — a CronJob cannot exist without
them, and no default would be honest. The command is optional (omit it to use
the image's own entrypoint); so are the history limit and the deadline (the
Kubernetes defaults apply).

## Contract

Every value you can write is pinned by an expect: the image, both digits of the
time inside the assembled cron string, the command list, both history limits and
the deadline.
