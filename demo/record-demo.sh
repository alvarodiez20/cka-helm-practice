#!/usr/bin/env bash
# ============================================================
#  cka-practice · demo/record-demo.sh
#
#  Records a scripted terminal walkthrough of the exam suite and
#  turns it into a GIF and an animated SVG for the README and for
#  LinkedIn.
#
#  Run it on the machine that has the cluster (Killercoda, kind,
#  minikube). It types the commands for you at a readable pace,
#  so the recording is reproducible instead of depending on how
#  fast you type.
#
#    ./demo/record-demo.sh                 # the tour, cast + gif + svg
#    DEMO=kustomize ./demo/record-demo.sh  # one exam in depth
#    DEMO=helm-oci  ./demo/record-demo.sh
#    ./demo/record-demo.sh --cast-only     # just the .cast, convert later
#    ./demo/record-demo.sh --render-only   # convert an existing .cast
#
#  DEMO picks the script; the exam it uses must be SEEDED first,
#  which 'cka use <name>' does for you.
#
#  Requirements
#    asciinema   the recorder            https://asciinema.org
#    agg         cast -> GIF             cargo install --git https://github.com/asciinema/agg
#    svg-term    cast -> SVG (optional)  npm i -g svg-term-cli
#
#  --cast-only needs only asciinema, and .cast files can be
#  converted anywhere, so recording on the cluster host and
#  rendering on your laptop is the usual split.
#
#  KEEP THIS FILE IN STEP WITH THE INTERFACE. The recording that
#  shipped with 1.x still typed 'exam3', 'q3 2' and 'grade3 2',
#  six months after 'cka use', 'q' and 'grade' replaced them —
#  so the README's demo taught commands the README did not
#  document. If you change the verbs, re-record.
# ============================================================
set -uo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
OUT="$HERE/out"
DEMO="${DEMO:-tour}"
NAME="${NAME:-cka-practice-${DEMO}}"
CAST="$OUT/${NAME}.cast"

# Typing speed and pauses. Slower is more readable; these are tuned so a
# ~45s recording stays legible when GitHub scales it down.
TYPE_DELAY="${TYPE_DELAY:-0.035}"   # seconds per character
PAUSE_SHORT="${PAUSE_SHORT:-0.8}"   # after a command finishes
PAUSE_LONG="${PAUSE_LONG:-2.2}"     # after something worth reading

# Terminal geometry. 100x30 is a good compromise: wide enough for helm
# output, small enough that the text stays sharp in a README.
COLS="${COLS:-100}"
ROWS="${ROWS:-30}"

G=$'\e[32m'; Y=$'\e[33m'; R=$'\e[31m'; BO=$'\e[1m'; D=$'\e[2m'; N=$'\e[0m'
ok(){   printf "  ${G}✔${N} %s\n" "$*"; }
warn(){ printf "  ${Y}!${N} %s\n" "$*"; }
die(){  printf "  ${R}✘${N} %s\n" "$*"; exit 1; }

MODE="all"
case "${1:-}" in
  --cast-only)   MODE="cast" ;;
  --render-only) MODE="render" ;;
  ""|--all)      MODE="all" ;;
  -h|--help)     sed -n '2,37p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *)             die "unknown option: $1  (try --help)" ;;
esac

mkdir -p "$OUT"

# ── the script the recording plays out ──────────────────────
# One command per line. Lines starting with # are shown as comments
# (typed out, but not executed), which is how the narration works.
# Lines starting with @ are pauses in seconds.
demo_script(){
  case "$DEMO" in
    # ── one exam, in depth: the Kustomize traps ─────────────
    # Deliberately no 'explain' here. A walkthrough is 80+ lines, which in a
    # 30-row frame is three screens of scroll in one blink — unreadable, and
    # expensive, because GIF size tracks distinct frames rather than duration.
    # The two greps below make the same point in two lines: the render has the
    # new tag, the base still has the old one.
    kustomize)
      cat <<'SCRIPT'
# Eleven mock CKA exams for the CKA, graded against a real cluster.
@1
cka
@4
cka use kustomize
@4
# Task 4: change the image without touching the manifest.
q 4
@4
# The kustomization sets the tag ...
kubectl kustomize ~/exam11/base | grep image:
@2
# ... and the base manifest still says what it always said.
grep -n image: ~/exam11/base/deployment.yaml
@3
# The grader checks both: the cluster, and that the base is untouched.
grade 4
@3
grade
@5
SCRIPT
      ;;

    # ── one exam, in depth: the --skip-crds trap ────────────
    helm-oci)
      cat <<'SCRIPT'
# Helm on the CKA, graded against a live cluster.
@1
cka use helm-oci
@3
# Task 2 is the one everybody gets wrong.
q 2
@3
# --skip-crds looks right. It does nothing to this chart.
helm template argocd argo/argo-cd --version 7.9.1 -n argocd --skip-crds | grep -c 'kind: CustomResourceDefinition'
@2
# The CRDs are in templates/, not crds/. So it needs the chart's own value.
helm template argocd argo/argo-cd --version 7.9.1 -n argocd --set crds.install=false > ~/answers3/q2.yaml
grep -c 'kind: CustomResourceDefinition' ~/answers3/q2.yaml
@2
# The grader reads the file and the cluster, not my answer.
grade 2
@3
# Stuck? Every task has a walkthrough that explains the trap.
explain 2
@6
grade
@4
SCRIPT
      ;;

    # ── the default: the whole interface in forty seconds ───
    # Five commands, which is the pitch. Nothing here is exam-specific,
    # so this one survives the exam set changing under it.
    *)
      cat <<'SCRIPT'
# Eleven mock CKA exams, graded against a real cluster.
@1
cka
@5
# Pick one. It is built in the cluster if it is not there yet.
cka use netpol
@6
# What should I do first?
next
@5
# ... solve it against the cluster, then:
kubectl -n frontend get networkpolicy
@3
grade 1
@3
# Wrong? The walkthrough gives the reasoning, not just the answer.
explain 4
@7
# And the score is the cluster's state, not a stored answer.
grade
@5
SCRIPT
      ;;
  esac
}

# ── the inner script that actually runs inside asciinema ────
# Written to a file because asciinema -c takes a single command.
build_player(){
  cat > "$OUT/.player.sh" <<PLAYER
#!/usr/bin/env bash
# Generated by record-demo.sh — replays the demo script with simulated typing.
set -uo pipefail
export PS1=''
# The exam scripts colour their output only when stdout is a tty AND TERM is
# usable. Inside asciinema stdout is a pty, so all that is missing is TERM.
export TERM="\${TERM:-xterm-256color}"
TYPE_DELAY=$TYPE_DELAY
PAUSE_SHORT=$PAUSE_SHORT
PAUSE_LONG=$PAUSE_LONG
PROMPT='\$ '

# Load the exam commands, so the recording shows 'cka use' rather than paths.
source "$ROOT/activate.sh" 2>/dev/null || true

type_out(){ # print a string one character at a time
  local s="\$1" i
  for (( i=0; i<\${#s}; i++ )); do
    printf '%s' "\${s:\$i:1}"
    sleep "\$TYPE_DELAY"
  done
}

run_line(){
  local line="\$1"
  case "\$line" in
    '')  return ;;
    @*)  sleep "\${line#@}"; return ;;
    '#'*)
      # Narration: type it as a shell comment, then just newline.
      printf '\e[1;36m%s\e[0m' "\$PROMPT"
      printf '\e[2m'; type_out "\$line"; printf '\e[0m\n'
      sleep "\$PAUSE_SHORT"
      return ;;
  esac
  printf '\e[1;36m%s\e[0m' "\$PROMPT"
  type_out "\$line"
  printf '\n'
  sleep 0.35
  eval "\$line" 2>&1 || true
  sleep "\$PAUSE_SHORT"
}

while IFS= read -r l; do run_line "\$l"; done < "$OUT/.script.txt"

printf '\e[1;36m%s\e[0m' "\$PROMPT"
sleep "\$PAUSE_LONG"
PLAYER
  chmod +x "$OUT/.player.sh"
}

# ── record ──────────────────────────────────────────────────
if [ "$MODE" != "render" ]; then
  command -v asciinema >/dev/null \
    || die "asciinema not found.  pip install asciinema   (or: brew install asciinema)"
  command -v kubectl >/dev/null && kubectl get nodes >/dev/null 2>&1 \
    || warn "no reachable cluster — the recording will show failures"

  demo_script > "$OUT/.script.txt"
  build_player

  rm -f "$CAST"
  printf "\n%s  Recording '%s'%s  %s(%sx%s, ~40s — do not touch the keyboard)%s\n\n" \
    "$BO" "$DEMO" "$N" "$D" "$COLS" "$ROWS" "$N"

  # --cols/--rows pin the geometry so the output does not depend on the
  # window this happens to run in. -q keeps asciinema's own banner out
  # of the recording.
  asciinema rec "$CAST" \
    --cols "$COLS" --rows "$ROWS" \
    --idle-time-limit 2 \
    --overwrite -q \
    -c "bash --noprofile --norc $OUT/.player.sh" \
    || die "recording failed"

  rm -f "$OUT/.player.sh" "$OUT/.script.txt"
  ok "cast written to $CAST"
fi

[ -f "$CAST" ] || die "no cast at $CAST — record one first (drop --render-only)"

if [ "$MODE" = "cast" ]; then
  printf "\n  Convert it later with:\n\n"
  printf "    agg --font-size 16 --theme asciinema %s %s/%s.gif\n\n" "$CAST" "$OUT" "$NAME"
  exit 0
fi

# ── render ──────────────────────────────────────────────────
if command -v agg >/dev/null; then
  # --font-size 16 keeps the GIF readable at README width; the default 14
  # goes fuzzy once GitHub scales it. --speed 1 keeps real timing.
  agg --font-size 16 --theme asciinema --speed 1 \
      "$CAST" "$OUT/${NAME}.gif" >/dev/null 2>&1 \
    && ok "GIF  $OUT/${NAME}.gif  ($(du -h "$OUT/${NAME}.gif" | cut -f1))" \
    || warn "agg failed"
elif python3 -c 'import pyte, PIL' >/dev/null 2>&1; then
  # agg wants a Rust toolchain. cast-to-gif.py wants two pip packages and
  # produces the same thing, so a host without cargo is not a dead end.
  ok "agg not found — falling back to demo/cast-to-gif.py"
  python3 "$HERE/cast-to-gif.py" "$CAST" "$OUT/${NAME}.gif" 15 10 \
    || warn "cast-to-gif.py failed"
else
  warn "no GIF renderer. Either:"
  warn "  cargo install --git https://github.com/asciinema/agg"
  warn "  pip install pyte pillow      # then demo/cast-to-gif.py"
fi

if command -v svg-term >/dev/null; then
  # An animated SVG is a fraction of the GIF's size and stays crisp on
  # retina screens. GitHub renders it in a README; LinkedIn does not.
  svg-term --in "$CAST" --out "$OUT/${NAME}.svg" \
           --window --width "$COLS" --height "$ROWS" >/dev/null 2>&1 \
    && ok "SVG  $OUT/${NAME}.svg  ($(du -h "$OUT/${NAME}.svg" | cut -f1))" \
    || warn "svg-term failed"
else
  warn "svg-term not found — no SVG.  npm i -g svg-term-cli"
fi

echo
printf "%s  Next%s\n\n" "$BO" "$N"
printf "    README    ![demo](demo/out/%s.gif)\n" "$NAME"
printf "    LinkedIn  upload the .gif directly — under 8 MB and it animates.\n"
printf "              If it is bigger, re-run with COLS=90 ROWS=26 or trim the script.\n\n"
printf "    %sGIF size is driven by the number of distinct frames, so longer%s\n" "$D" "$N"
printf "    %spauses are cheap and fast scrolling is expensive.%s\n\n" "$D" "$N"
