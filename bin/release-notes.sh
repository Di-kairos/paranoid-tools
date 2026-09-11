#!/usr/bin/env bash
# release-notes.sh — the body of a GitHub release for one tool, from its CHANGELOG.
#
# Usage: bin/release-notes.sh <tool> <tag> [--prev <tag>] [--summary <file>]
#
# `gh release create --generate-notes` writes a list of commit subjects, which for a tool whose
# changelog is kept by hand is the weaker of the two: the changelog says what changed for the
# person installing it, the commit list says what changed for the person who wrote it. So the
# release body is the CHANGELOG section of the tagged version, verbatim, plus what every release
# page should carry next to the download buttons — how to verify the files before running them.
# The changelogs are written in Russian (README: "release notes written in Russian; what they
# describe is in the English docs"); --summary prepends an English paragraph when there is one.
#
# release.yml runs this on every tag; the same script backfilled the releases cut before it
# existed, so old and new pages read the same.
set -euo pipefail

tool="${1:?tool}"; tag="${2:?tag}"; shift 2
prev=""; summary=""
while [ $# -gt 0 ]; do
  case "$1" in
    --prev)    prev="${2:?}"; shift 2 ;;
    --summary) summary="${2:?}"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

root="$(cd "$(dirname "$0")/.." && pwd)"
repo="${GITHUB_REPOSITORY:-Di-kairos/paranoid-tools}"
ver="${tag#"$tool-v"}"
changelog="$root/$tool/CHANGELOG.md"
[ -f "$changelog" ] || { echo "no changelog: $changelog" >&2; exit 1; }

# The section between "## [X.Y.Z]" and the next "## [": exact version, so 0.5.8 never picks up 0.5.80.
section="$(awk -v v="$ver" '
  $0 ~ "^## \\[" v "\\]" { f = 1; next }
  /^## \[/ { if (f) exit }
  f' "$changelog" | sed -e '/./,$!d' | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}')"
if [ -z "$(printf '%s' "$section" | tr -d '[:space:]')" ]; then
  echo "CHANGELOG.md of $tool has no section for $ver — write it before tagging" >&2
  exit 1
fi

# Same key every installer pins. A release page that shows the download buttons and not the
# check is a page that teaches the weaker path as if it were the path.
pub='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH9DVd0vNOwa5hyr9gShaCWoNOVnUsrdHVO/WE0wCZkT'
base="https://github.com/$repo/releases/download/$tag"

if [ -n "$summary" ]; then
  cat "$summary"; printf '\n'
fi

cat <<EOF
### What changed

_From [\`$tool/CHANGELOG.md\`](https://github.com/$repo/blob/$tag/$tool/CHANGELOG.md) — the changelogs are kept in Russian; the English [README](https://github.com/$repo/blob/$tag/$tool/README.md) describes the same tool at this version._

$section

### Verify before you run anything

The six files above are signed as one set: \`SHA256SUMS.sig\` is an Ed25519 signature over
\`SHA256SUMS\`, and every installer pins the same public key. Check it yourself — this is the
whole claim of the project, executable:

\`\`\`bash
base=$base
curl -fsSLO "\$base/install.sh"; curl -fsSLO "\$base/SHA256SUMS"; curl -fsSLO "\$base/SHA256SUMS.sig"
printf '%s\\n' 'releases@paranoid-tools namespaces="file" $pub' > allowed_signers
ssh-keygen -Y verify -f allowed_signers -I releases@paranoid-tools -n file -s SHA256SUMS.sig < SHA256SUMS
shasum -a 256 -c SHA256SUMS --ignore-missing   # then read install.sh, then run it
\`\`\`

On Windows the same files are \`install.ps1\` and \`$tool.ps1\`; \`install.ps1\` runs the same
check before it installs. From a clone, \`bash verify-releases.sh\` checks the current release
of all five tools at once.

**Install:** [\`$tool/README.md\`](https://github.com/$repo/blob/$tag/$tool/README.md#install) ·
all five at once: [root README](https://github.com/$repo#install).
EOF

if [ -n "$prev" ]; then
  printf '\n**Full changelog**: https://github.com/%s/compare/%s...%s\n' "$repo" "$prev" "$tag"
fi
