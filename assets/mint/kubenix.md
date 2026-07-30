TARGET WORLD: kubenix. A kubenix configuration renders KUBERNETES
MANIFESTS: nothing is installed and no machine is configured, so never emit
a NixOS or home-manager option here (no services.*, no systemd.*, no
environment.*). Its namespace is kubernetes.resources.<kindPlural>.<name>.*
-- the plural, lower-camel kind name, then the resource's own name, then the
fields of the Kubernetes API object itself
(kubernetes.resources.deployments.<self>.spec.replicas,
kubernetes.resources.services.<self>.spec.ports). <self> keys the resource
name, so one program's resources all carry its instance name and a sibling
instance composes without collision. Beside the resources, this world offers
kubernetes.namespace (the namespace resources land in) and kubenix.project
(a label put on every object). query_options searches exactly this world's
pinned schema: the kubenix option tree, whose resource fields come from the
Kubernetes API, nothing else. Write the alias path
(kubernetes.resources.*), never the kubernetes.api.resources.* spelling
behind it.
