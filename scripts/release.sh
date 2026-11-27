#!/usr/bin/env bash
# Tags a release and pushes the tag; the Release workflow does the rest
# (builds the image, tests that build, publishes it, creates the GitHub
# Release). Run it through `make release VERSION=2.28.5-tosca.N`.
#
# It tags only when the release workflow would accept the tag: the checkout is
# clean and is exactly origin/main, the GeoServer version in docker/Dockerfile
# and a CHANGELOG.md section match, and the tag does not exist yet.
set -Eeuo pipefail
cd "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.."

name=tosca-geoserver
repo=geoserver_docker
version=${1:-}
version=${version#v}
die() { echo "Cannot release: $*" >&2; exit 1; }

[[ $version =~ ^([0-9]+\.[0-9]+\.[0-9]+)-tosca\.[0-9]+$ ]] \
  || die "VERSION must be <GeoServer version>-tosca.<n>, e.g. make release VERSION=2.28.5-tosca.2"
geoserver=${BASH_REMATCH[1]}
tag=v$version

[[ -z $(git status --porcelain) ]] || die "the working tree has uncommitted changes."
git fetch -q --tags origin main
[[ $(git rev-parse HEAD) == "$(git rev-parse origin/main)" ]] \
  || die "this checkout is not at origin/main. Run: git checkout main && git pull"

declared=$(sed -n 's/^ARG GEOSERVER_VERSION=//p' docker/Dockerfile)
[[ $geoserver == "$declared" ]] \
  || die "docker/Dockerfile builds GeoServer $declared, not $geoserver."
grep -q "^## \[$version\]" CHANGELOG.md \
  || die "CHANGELOG.md has no '## [$version]' section. Add it in a pull request first."

[[ -z $(git tag -l "$tag") ]] || die "tag $tag already exists."
[[ -z $(git ls-remote --tags origin "refs/tags/$tag") ]] || die "tag $tag already exists on GitHub."

git tag -a "$tag" -m "$name $version"
git push origin "$tag"
echo "Pushed $tag. The Release workflow now builds, tests and publishes $name:$version:"
echo "  https://github.com/digitalcityscience/$repo/actions/workflows/release.yml"
