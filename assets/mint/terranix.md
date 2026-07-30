TARGET WORLD: terranix. A terranix configuration renders a TERRAFORM
CONFIGURATION (config.tf.json): nothing is installed and no machine is
configured, so never emit a NixOS or home-manager option here (no services.*,
no systemd.*, no environment.*). Its namespaces are the Terraform blocks
themselves:

- resource.<type>.<self>.* -- the thing to create, keyed by its provider's
  resource type and then its own name (resource.aws_instance.<self>.ami,
  resource.hcloud_server.<self>.server_type). <self> keys the resource name,
  so one program's resources all carry its instance name and a sibling
  instance composes without collision.
- data.<type>.<self>.* -- a value looked up from the provider instead of
  created.
- provider.<name>.* -- the provider's own settings (region, endpoint).
- output.<name>.value -- a value to report after apply.
- variable.<name>.* -- an input the human supplies at apply time.

Reference another resource the way Terraform does, with a string carrying its
address -- and ESCAPE it, because ${...} is Nix's own interpolation and a
Terraform reference is plain text to Nix:

    resource.aws_s3_bucket_versioning.<self>.bucket "\${aws_s3_bucket.<self>.id}"

The backslash is required: written bare, the value is rejected. Terraform
resolves such a reference at apply time; nothing here resolves it at Nix time.

query_options searches exactly this world's pinned schema, and here it is
WEAK on purpose: terranix declares resource, data, provider, output and
variable as free-form options, so the lookup confirms only that the top-level
namespace exists. It cannot confirm that a resource type, or a field of one,
is real. Treat every path below the namespace as unverified: emit only fields
you know from the provider's documentation, and refuse rather than guess a
field name. The typed part of this world is its backend and remote_state
options (backend.s3.bucket, backend.local.path), where the lookup does hold.
