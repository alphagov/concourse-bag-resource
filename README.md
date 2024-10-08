# Concourse Bag Resource

This is a concourse resource type that records the versions of other concourse resources
("sub-resources") in a git repository, and then allows this collection of versions to be
"replayed" later or elsewhere.

Notionally it "packs" these resource versions into a "bag" from which they can later be
"unpacked".

This can be used to create deployments that have greater control and certainty over the
exact set of resource versions used to perform a particular deployment. With bag-resource,
a problematic deployment can have all of its inputs rolled-back together to a the last
known-good set of input versions using a single resource pin (or unticking). A deployment
that was successful on one pipeline can be marked as such with a single tag on the bag's
git repository revision and the deployment can then be reproduced in another pipeline.

The bag-resource attempts to bring some of the deployment-time advantages of a monorepo
for non-monorepo projects and projects that have a mixture of input types that don't
necessarily fit into a git repository.

Though the bag-resource is designed to pack arbitrary other resource types, those
resource types need to be specified at image build time and it has currently only
been tested with the git resource and the registry-image resource.

## How does it work?

The bag-resource _embeds_ copies of the supported resource types' container images
in sub-directories and forwards calls to their `in`, `out` and `check` scripts using
[`proot`](https://proot-me.github.io/) with parameters adjusted accordingly.

Resource versions are recorded in the bag repository using the `version` json format
of the underlying resource (as used to [communicate versions](https://concourse-ci.org/implementing-resource-types.html#resource-check)
between the `check` and `in` scripts). This makes it agnostic of the underlying resource
type.

## `source` configuration

A bag-resource can operate in one of two modes: "bag" mode and "proxy" mode, with "proxy"
mode being a light wrapper around a single underlying resource that gives it the ability
to be used as an input when packing a bag-resource in "bag" mode.

- `bag_repo`: the `git-resource` configuration for the "bag" repository. The contents of
  this are forwarded directly to `git-resource`'s `source` section when attempting to
  access the "bag" repository. Supplying this key implies this resource is working in "bag"
  mode. Required in "bag" mode.

- `subresources`: a mapping of _(subresource-name)_ to _(subresource-configuration)_. A
  "subresource" describes one of the resources contained by the bag. Supplying this key
  implies this resource is working in "bag" mode. Required in "bag" mode.
  - _(subresource-name)_:
    - `type`: currently either `git` or `registry-image`. Required.
    - `source`: the `source` section to be passed to the underlying resource when
      performing a `get` (an `in` script call) of the subresource. This should include the
      details required to access the resource (e.g. location and credentials), but this
      should be unrestricted in which versions it can fetch, because version _selection_
      is the responsibility of the resource (likely another bag-resource in `proxy` mode)
      that's used to feed the "packing" of the bag. In fact, many keys which resources use
      to select versions are only used in the `check` phase and placed in this section they
      would have no effect, this section only being used in the `get` phase. To
      prevent any potential confusion, some keys are specifically disallowed from this
      section (see [disallowed-subresource-source-keys](assets/disallowed-subresource-source-keys)).
      Required.

- `proxy`: operate this bag-resource in "proxy" mode where it simply augments the
  capabilities of a single underlying resource.
  - `type`: currently either `git` or `registry-image`. Required.
  - `source`: passed directly as the `source` of the underlying resource. Required.

## Behaviour

### `check`

In "bag" mode this checks for new commits to the `bag_repo`.

In "proxy" mode this is handled by the proxied resource.

### `in` ("`get`")

In "bag" mode this will fetch the appropriate revision of the `bag_repo` and then populate
the output directory with it (under the `bag_repo/` or `.bag_repo/` directories) and then,
based on the versions recorded in bag repository checkout, fetch any requested subresources
to the output directory.

#### Parameters ("bag" mode)

- `subresources`: a mapping of _(subresource-name)_ to _(subresource-configuration)_. Without this,
  only the `bag_repo` will be fetched.
  - _(subresource-name)_:
    - `flatten`: boolean - if `true`, this sub-resource will be fetched directly to the root
      of the output directory. Only a single subresource can be fetched in this case. This was
      created so that `registry-image` subresources could be fetched in `rootfs` format and
      fed directly to concourse as a [task-step image](https://concourse-ci.org/task-step.html#schema.task.image),
      concourse being extremely fussy about being given an output name here, not allowing
      sub-directories to be specified. The bag repository is placed in `.bag_repo/` if
      flattening. Default `false`.
    - `params`: passed through to underlying resource. Default `{}`.

> [!TIP]
> While it's possible to list multiple subresources to be fetched in one `get` operation, this
> will be done serially. So it's often better to perform several separate `get` operations in
> an `in_parallel` block, as it will also result in clearer error messages if one subresource
> is to fail. This is at the expense of greater number of `bag_repo` fetches.

In "proxy" mode, either a regular fetch of the underlying resource can be performed or the
version information can be exposed for use in bag-packing.

#### Parameters ("proxy" mode)

- `version_only`: boolean - if `true`, instead of fetching the actual underlying resource,
  the contents of the `in` call's `version` field will be serialized to the output directory
  under the filename `version.json`. This can then be used to assemble a new bag revision
  in the `put` operation of a bag-resource in `bag` mode. Default `false`
- `proxy`: contents passed through to `params` of underlying proxied resource for performing a
  regular fetch.

### `out` ("`put`")

In "bag" mode this will optionally assemble a new bag revision and push this revision to a
remote repository, operating similarly to how `put`ting to a git-resource works

#### Parameters ("bag" mode)

- `path`: for assembling a new bag revision, this specifies the path of a directory to which
  a bag resource has previously been fetched (*not* in `proxy` or `flatten` mode - a `bag_repo`
  subdirectory is expected to be found). When `path` is specified, the `put` phase will look
  for each subresource's `version.json` under a directory with the same name as the subresource.
  These will then be assembled, committed and pushed to the remote `bag_repo`.

- `bag_repo`: parameters passed to the `params` of the underlying git-resource when pushing to
  the remote bag repository.
  - _(arbitrary parameters)_
  - `repository`: if the `repository` key is provided, the automatic bag-packing procedure is
    skipped and it is assumed that `repository` points to a manually prepared directory for
    pushing to the `bag_repo`. In this case operation is identical to git-resource's `put`.
    Notably, no checking will be performed for the validity of the contents.

In "proxy" mode a regular push to the underlying resource will be performed.

#### Parameters ("proxy" mode)

- `proxy`: contents passed through to `params` of underlying proxied resource for performing a
  regular `put`.
