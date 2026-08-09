<!-- Written by `lips generate`. Every mint overwrites it; edits are lost. -->

# The `bucket` language

This language describes one S3 file store per program, and it renders a
Terraform configuration (`config.tf.json`) -- nothing is installed on any
machine.

## The three sentences it reads

- `store files in the aws region <region>.` -- the only required line. The
  region is a hole: it configures the `aws` provider (`provider.aws.region`)
  and it is what makes the bucket exist at all. This line creates
  `resource.aws_s3_bucket.<self>`, where `<self>` is the program's instance
  name (the middle part of the filename, `assets` for `assets.bucket.lips`),
  so two such programs compose in one configuration without colliding.
- `keep every version of a file.` -- optional. It adds
  `resource.aws_s3_bucket_versioning.<self>` pointing at the bucket
  (`bucket = "${aws_s3_bucket.<self>.id}"`, escaped so Nix passes the
  reference through to Terraform verbatim) with
  `versioning_configuration.status = "Enabled"`. This is the modern,
  separate-resource form of bucket versioning, not the deprecated inline
  `versioning` block.
- `report the bucket name after apply.` -- optional. It adds an output named
  after the instance (`output.<self>`) whose value is the bucket's id and
  whose description is the phrase the sentence used ("bucket name"), so
  `terraform apply` prints the real name.

Line shapes are fixed except for the region; a sentence lips cannot match
fails the build at compile time, so keep the wording as above.

## Choices I made, and why

- **The bucket has no explicit name.** No program line states one, and the
  third sentence ("report the bucket name after apply") only makes sense for
  a name that is not known beforehand -- so I let the AWS provider generate a
  unique bucket name and let the output report it. I did not invent a name
  and I did not demand one, since no line shape in these programs states one.
  If you want to name buckets yourself, that is a new sentence and needs a
  fresh `generate`.
- **`force_destroy = false`** is emitted on the bucket. A Terraform resource
  block needs at least one argument to be written out, and this is the
  provider's own default made explicit: a bucket that still holds objects is
  never silently destroyed. It is a constant of the mechanism, not a value
  you are expected to edit.
- **Region lives on the provider**, not on the bucket resource: that is the
  portable spelling across AWS provider versions.
- Nothing is said about a state backend, so none is configured; state stays
  local unless you add one.

## What the contract pins

`<language>.expect` checks, on every future compile, that the region you
write lands in `provider.aws.region`, that versioning really reads `Enabled`
on the versioning resource, and that the report line produces the output
description. Those are the three places a program's own words reach the
rendered Terraform.
