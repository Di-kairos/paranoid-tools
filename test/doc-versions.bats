# One source of versions. The audit of 2026-09-07 (F08) found user-facing install docs pinned to
# versions two releases behind the code — a reader who follows them installs something other than
# what the page describes. release.yml already keeps install.sh, the umbrella version map and
# verify-releases.sh in lockstep with the tag; prose was the part nobody checked.
#
# Only install instructions are checked — a release-download URL and a `<TOOL>_VERSION=` pin.
# Historical mentions ("since v0.3.0", changelogs) are none of this test's business.

setup() { ROOT="${BATS_TEST_DIRNAME}/.."; }

_tool_version() { grep -m1 -E '^VERSION=' "$ROOT/$1/$1" | sed 's/.*=//;s/"//g'; }

_docs_of() {
  local t="$1" f
  for f in "$t/README.md" "$t/README.ru.md" "$t/SECURITY.md" "$t/windows/README.md"; do
    [ -f "$ROOT/$f" ] && printf '%s\n' "$ROOT/$f"
  done
}

@test "release-download URLs in the tool docs point at the current version" {
  local t v bad=""
  for t in securetrash vaultwatch panic ghostdraft seedsplit; do
    v="$(_tool_version "$t")"
    while read -r f; do
      while read -r hit; do
        [ -z "$hit" ] && continue
        [[ "$hit" == "$t-v$v" ]] || bad="${bad}${f#$ROOT/}: $hit (code says $v)"$'\n'
      done < <(grep -ohE "$t-v[0-9]+\.[0-9]+\.[0-9]+" "$f" || true)
    done < <(_docs_of "$t")
  done
  [ -z "$bad" ] || { printf '%s' "$bad"; false; }
}

@test "the <TOOL>_VERSION pin examples match the current version" {
  local spec t var v bad=""
  for spec in securetrash:ST_VERSION vaultwatch:VW_VERSION panic:PANIC_VERSION \
              ghostdraft:GHOSTDRAFT_VERSION seedsplit:SEEDSPLIT_VERSION; do
    t="${spec%%:*}"; var="${spec##*:}"; v="$(_tool_version "$t")"
    while read -r f; do
      while read -r hit; do
        [ -z "$hit" ] && continue
        [[ "$hit" == "$var=$v" ]] || bad="${bad}${f#$ROOT/}: $hit (code says $v)"$'\n'
      done < <(grep -ohE "$var=[0-9]+\.[0-9]+\.[0-9]+" "$f" || true)
    done < <(_docs_of "$t")
  done
  [ -z "$bad" ] || { printf '%s' "$bad"; false; }
}

@test "a page that shows a pipe-install also shows the verify-then-run path" {
  # `curl … | bash` / `irm … | iex` execute the installer before the reader sees a byte of it.
  # The tool READMEs may show it as the quick form, because they put the verify-then-run block
  # (pinned key, ssh-keygen -Y verify, read it, then run) right next to it and say plainly what
  # piping costs. A page that shows only the pipe — as securetrash's landing page did until the
  # 2026-09-07 audit (F08) — teaches the weaker path as if it were the path.
  local f bad=""
  while read -r f; do
    [ -z "$f" ] && continue
    grep -q 'ssh-keygen -Y verify' "$f" || bad="${bad}${f#$ROOT/}"$'\n'
  done < <(grep -rlE 'curl [^|]*\| *(bash|sh)|irm [^|]*\| *iex' \
             "$ROOT"/README.md "$ROOT"/README.ru.md "$ROOT"/GUIDE.md "$ROOT"/ИНСТРУКЦИЯ.md \
             "$ROOT"/*/README.md "$ROOT"/*/README.ru.md "$ROOT"/*/windows/README.md \
             "$ROOT"/*/docs/index.html 2>/dev/null || true)
  [ -z "$bad" ] || { printf 'pipe-install without the verify-then-run path:\n%s' "$bad"; false; }
}

# The share format in the docs is an example a reader copies expectations from, and it drifted:
# GUIDE and ИНСТРУКЦИЯ still printed an SSS2 template long after the code moved to SSS3 with a
# parity field (audit 2026-09-07, §16.7). Version pins were already guarded; the wire format was
# not. Only example TEMPLATES are checked — they are the lines carrying the literal `<setid>`,
# so prose about reading legacy SSS2 shares stays untouched.
@test "share-format examples in the docs use the current wire format" {
  local current bad=""
  current="$(grep -o 'SSS[0-9]\+-\${setid_hex}' "$ROOT/seedsplit/seedsplit" | head -1 | sed 's/-.*//')"
  [ -n "$current" ]
  while read -r hit; do
    case "$hit" in *"$current-<setid>"*) ;; *) bad="$bad$hit"$'\n' ;; esac
  done < <(grep -rn 'SSS[0-9]\+-<setid>' \
             "$ROOT"/README.md "$ROOT"/README.ru.md "$ROOT"/GUIDE.md "$ROOT"/ИНСТРУКЦИЯ.md \
             "$ROOT"/seedsplit/README.md "$ROOT"/seedsplit/README.ru.md 2>/dev/null || true)
  [ -z "$bad" ] || { echo "superseded share format in docs (current is $current):"; echo "$bad"; false; }
}
