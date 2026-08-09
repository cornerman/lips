<!-- Written by `lips generate`. Every mint overwrites it; edits are lost. -->

# The `deploy` language

This language describes one containerised web workload per program and turns it
into a Kubernetes Deployment plus a matching Service, both named after the
program's own instance name (the file basename, e.g. `web` for
`web.deploy.lips`).

## The four sentences it accepts

- `run <count> replicas of the image <image>.` — states two things at once: the
  replica count (`spec.replicas` of the Deployment) and the container image with
  its tag (the single container, keyed `app`, in the pod template). The image is
  captured as one token, so `nginx:1.27` stays intact, tag and all; the trailing
  period is not part of it.
- `listen on container port <port>.` — the port the process inside the container
  binds. It lands twice, because the same number is meant twice: as the
  container's `containerPort` and as the Service's `targetPort`.
- `expose it in the cluster on port <port>.` — the port the Service publishes.
  "in the cluster" is not a value but the words that pick the mechanism: the
  Service is of type `ClusterIP`.
- `deploy into the namespace <ns>.` — sets `kubernetes.namespace`, the namespace
  every rendered object goes into.

Every number in these lines is written into an integer-typed field, so a
non-numeric word fails at compile time rather than at `kubectl apply` time.

## Vocabulary

Facts are named the way the sentences talk, not the way the API does:
`deploy.replicas`, `deploy.image`, `deploy.port`, `deploy.namespace`,
`service.port`. That is the surface future programs are written against; the
API paths behind them are the engine's business.

## What must be stated

All four sentences except the namespace one are demanded: a Deployment with no
image or no replica count, and a Service with no cluster port or no target
port, are not things this language will silently guess at. The namespace line is
optional only because leaving it out means kubenix's own default namespace —
that is a platform default, not an invention of mine. Note that
`kubernetes.namespace` is one value for the whole rendered configuration, so two
programs compiled together must agree on it; disagreeing lines fail the build,
which is the honest outcome.

## The one thing I had to choose

Nothing in the program says how the Service should find the Deployment's pods,
but a Service without a selector routes nowhere. I label the pod template with
the program's own instance name as the label key and the constant value `app`
(`labels: { web: "app" }`), and use exactly that pair for the Deployment's
`spec.selector.matchLabels` and the Service's `spec.selector`. Keying the label
on the instance name rather than on a fixed `app: <something>` means two sibling
programs in the same namespace — even two running the same image — can never
cross-select each other's pods. If you would rather see a conventional
`app: <name>` label, that is a value the program would have to state, and it
would need a new sentence.

The container is always keyed `app` and its port always keyed `http` inside the
pod; those keys are internal names, not values from the program, so they stay
fixed.
