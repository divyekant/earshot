# Branches, versions and releases

This document tells you how a change goes from a branch to a release.

## Branches

| Branch | Content | Who merges into it |
|---|---|---|
| `develop` | The integration branch. All feature and fix pull requests go here. | Feature and fix pull requests. |
| `main` | Released code only. Each commit on `main` is a release. | Release pull requests from `develop`, and hotfix pull requests. |
| Topic branch | One change. Make it from `develop`. | Nobody. Delete it after the merge. |

Do not push directly to `develop` or `main`. Use a pull request.

## Version numbers

earshot uses [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html): `MAJOR.MINOR.PATCH`.

- The `VERSION` file at the root holds the version of the latest release, or of the release in preparation.
- `app/scripts/build-app.sh` writes the `VERSION` value into the app bundle (`CFBundleShortVersionString`).
- Before 1.0.0, increase MINOR for new features or for changes that are not compatible. Increase PATCH for fixes only.

## Tags

| Tag | When | GitHub release |
|---|---|---|
| `vX.Y.Z-dev.N` | Each merge into `develop`. The workflow `.github/workflows/prerelease.yml` makes it. | Pre-release, with notes generated from the pull requests. |
| `vX.Y.Z` | Each merge into `main`. The workflow `.github/workflows/release.yml` makes it. | Release, with notes from the `CHANGELOG.md` section of `X.Y.Z`. |

The pre-release workflow calculates `X.Y.Z` as follows:

- If the tag `v<VERSION>` does not exist, `X.Y.Z` is the `VERSION` value.
- If the tag `v<VERSION>` exists, `X.Y.Z` is the next MINOR version. For example, after `v0.1.0`, the next pre-release tags are `v0.2.0-dev.1`, `v0.2.0-dev.2`, and so on.

`N` starts at 1 for each `X.Y.Z`.

Do not make, move or delete a tag by hand. If a workflow fails, fix the cause and run the workflow again from the **Actions** tab.

## Send a change

1. Make a topic branch from `develop`.
2. Make the change.
3. Add one line for the change under `## [Unreleased]` in `CHANGELOG.md`. Use the correct group: `Added`, `Changed`, `Fixed`, `Removed` or `Security`. Write the line for a user of earshot, and include the requirement IDs.
4. Open a pull request with `develop` as the base.
5. Make sure that the check **Swift build and test** (workflow **CI**) passes.
6. Merge the pull request with a merge commit.

If the change is not visible to a user (for example, a test or a document only), you can omit the `CHANGELOG.md` line.

## Make a release

1. Make a topic branch from `develop`, for example `release/0.2.0`.
2. Set the new version in `VERSION`.
3. In `CHANGELOG.md`, change `## [Unreleased]` to `## [X.Y.Z] - YYYY-MM-DD`. Add a new, empty `## [Unreleased]` above it.
4. Update the compare links at the bottom of `CHANGELOG.md`.
5. Open a pull request to `develop` with the title `Prepare vX.Y.Z`, and merge it.
6. Open a pull request from `develop` to `main` with the title `Release vX.Y.Z`.
7. Make sure that the checks **Release check** and **Swift build and test** pass. The check makes sure that the version is new and that `CHANGELOG.md` has a section for it.
8. Merge the pull request with a merge commit. Do not squash or rebase, because `develop` and `main` must keep the same history.
9. Make sure that the workflow **Release** made the tag `vX.Y.Z` and the GitHub release.

## Make a hotfix

Use a hotfix only for a bad bug in a release that cannot wait for the next release.

1. Make a topic branch from `main`, for example `hotfix/0.2.1`.
2. Fix the bug. Increase PATCH in `VERSION`. Add a `## [X.Y.Z] - YYYY-MM-DD` section to `CHANGELOG.md`.
3. Open a pull request to `main` with the title `Release vX.Y.Z`, and merge it with a merge commit.
4. Open a pull request from `main` to `develop`, and merge it with a merge commit. This puts the fix on `develop`.
