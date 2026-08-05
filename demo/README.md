# Showing how it works

The repo is a terminal tool, so the demo has to be a terminal. This directory
holds the recorder; the assets it produces are build output and are **not**
committed.

> **Why nothing is committed here.** The GIF that shipped through 1.x still
> typed `exam3`, `q3 2` and `grade3 2` long after `cka use`, `q` and `grade`
> became the documented interface — so the first thing a reader saw taught
> them commands the README no longer mentioned. A recording is a snapshot of
> an interface, it goes stale silently, and nothing in CI can tell. Record it,
> attach it to the release or to the LinkedIn post, and re-record when the
> verbs change.

## The short version

On the machine with the cluster (Killercoda, kind, minikube):

```bash
pip install asciinema
cargo install --git https://github.com/asciinema/agg   # GIF renderer

source ./activate.sh
cka use netpol                # seed whatever the script needs

./demo/record-demo.sh                  # the tour
DEMO=kustomize ./demo/record-demo.sh   # one exam in depth
DEMO=helm-oci  ./demo/record-demo.sh
```

You get `demo/out/cka-practice-tour.{cast,gif,svg}`. The script types the
commands itself at a fixed pace, so the recording is reproducible and you are
not fighting your own typos.

Recording and rendering can be split — `.cast` files are plain JSON and convert
anywhere:

```bash
./demo/record-demo.sh --cast-only    # on the cluster host, needs only asciinema
./demo/record-demo.sh --render-only  # on your laptop, needs agg
```

## If you cannot install agg

`agg` needs a Rust toolchain, which is a lot to ask of a cluster host you are
about to throw away. `demo/cast-to-gif.py` renders the same thing with two pip
packages:

```bash
pip install pyte pillow
python3 demo/cast-to-gif.py demo/out/foo.cast demo/out/foo.gif [font_size] [fps]
```

It replays the cast through a terminal emulator and writes one GIF frame per
*distinct* screen, with each frame's duration taken from the cast's own
timings. That is the same trick `agg` uses, and it is why the size advice below
holds for both: a long pause is one cheap frame, and fast scrolling is many
expensive ones. `record-demo.sh` falls back to it automatically when `agg` is
not on PATH.

## The committed asset

`demo/cka-practice-kustomize.{cast,gif}` is what the README shows. Its terminal
output is a real run of exam 11 — real `kubectl`, real kustomize, the real
grader, a real 0/100-then-100/100 — captured against a live API server. The
typing and the pauses are scripted, exactly as `record-demo.sh` scripts them,
so the recording is reproducible rather than a function of how fast anyone
types.

**Re-record it when the verbs change.** That is the failure this file exists to
prevent: the GIF that shipped through 1.x still typed `exam3` and `q3 2` months
after `cka use`, `q` and `grade` replaced them.

## Recording on Killercoda

The [CKA playground](https://killercoda.com/playgrounds/scenario/cka) needs a
login, and its session is x86_64 Ubuntu. Paste this in one go:

```bash
# 1. install and load the commands
curl -sL https://raw.githubusercontent.com/alvarodiez20/cka-practice/main/bootstrap.sh | EXAM=none bash
source ~/cka-practice/activate.sh
cka use netpol      # or whichever exam the script you are recording uses

# 2. bootstrap.sh does not fetch the recorder, so get it separately
mkdir -p ~/cka-practice/demo
curl -fsSL -o ~/cka-practice/demo/record-demo.sh \
  https://raw.githubusercontent.com/alvarodiez20/cka-practice/main/demo/record-demo.sh
chmod +x ~/cka-practice/demo/record-demo.sh

# 3. recorder + renderer (prebuilt agg binary, no Rust toolchain needed)
pip install asciinema || apt-get install -y asciinema
curl -fsSL -o /usr/local/bin/agg \
  https://github.com/asciinema/agg/releases/latest/download/agg-x86_64-unknown-linux-gnu
chmod +x /usr/local/bin/agg

# 4. record
cd ~/cka-practice && ./demo/record-demo.sh
```

Solve the exam before recording if you want the closing `grade` to come up
green — `solve N` prints the commands for each task, and `examhelp` gives the
order they depend on.

Getting the result off the Killercoda VM: serve it and use the session's
traffic-port feature.

```bash
cd ~/cka-practice/demo/out && python3 -m http.server 8080
```

Then open port 8080 from the Killercoda UI and download the `.gif`. The `.cast`
is only a few KB, so an alternative is to `cat` it, copy the JSON out, and run
`agg` on your laptop instead.

## The options, and what each one is actually good for

| Format | Where it works | Size | Trade-off |
|---|---|---|---|
| **Animated GIF** (`agg`) | README, LinkedIn, X, Slack, anywhere | ~1–4 MB | The only animated format LinkedIn accepts. Fixed resolution, so text softens if scaled. |
| **Animated SVG** (`svg-term-cli`) | README, docs sites | ~100–400 KB | Crisp at any zoom, tiny, text is selectable. GitHub renders it; LinkedIn does not. |
| **asciinema player embed** | Your own site, asciinema.org | KB | Viewer can pause, scrub and copy the text. Needs JS, so not in a README. |
| **MP4 screen recording** | LinkedIn (as native video) | 5–50 MB | LinkedIn's algorithm favours native video, and you can narrate. Heavier to produce and to re-shoot. |
| **Static screenshots** | README, LinkedIn carousel | KB | No motion, but no autoplay problem either, and a carousel gets more dwell time than a single image. |
| **Killercoda / Codespaces link** | Anywhere | — | Strongest proof: the reader runs it themselves. Pairs with a GIF, does not replace it. |

### Recommendation

Use two assets, not one.

- **README**: animated SVG at the top, because it stays sharp and adds
  ~200 KB to a clone rather than a few MB. Fall back to the GIF if you want it
  to work in places that strip SVG (npm, PyPI, some doc renderers).
- **LinkedIn**: the GIF. It autoplays in-feed, it loops, and it needs no
  click. A 40-second GIF under 8 MB is safe; above that LinkedIn transcodes it
  into a still.

Then add the one-line `curl | bash` under both. A demo that shows a grader
working is interesting; a demo the reader can run in 30 seconds is what gets
the star.

## Tuning the recording

All of these are environment variables:

```bash
COLS=90 ROWS=26 ./demo/record-demo.sh        # smaller frame, smaller GIF
TYPE_DELAY=0.05 ./demo/record-demo.sh        # slower typing
PAUSE_LONG=3 ./demo/record-demo.sh           # more time to read output
NAME=tour-short ./demo/record-demo.sh        # output filename
DEMO=kustomize ./demo/record-demo.sh         # which script to play
```

Practical notes learned the hard way:

- **GIF size tracks distinct frames, not duration.** Long pauses are almost
  free; a fast `helm template` dump that scrolls hundreds of lines is
  expensive. If the GIF is too big, cut scrolling output before cutting pauses.
- **100×30 is the sweet spot.** Wider and the text is unreadable once GitHub
  scales it to content width; narrower and `helm list` output wraps.
- **`--font-size 16`** in `agg` (the default 14 goes fuzzy after scaling).
- **Keep it under ~45 seconds.** Feed viewers give a GIF about three seconds
  to earn the next three.

## What the demo script shows

Edit `demo_script()` in `record-demo.sh` to change it. The format is one
command per line, `#` for narration typed as a comment, `@2` for a two-second
pause.

There are three:

| `DEMO=` | Shows | Ages well? |
|---|---|---|
| `tour` (default) | the whole interface in five commands — `cka`, `cka use`, `next`, `grade`, `explain` | yes: nothing in it is exam-specific, so adding or renaming an exam does not invalidate it |
| `kustomize` | the `images:` transformer trap, then `grade 4` reading the cluster *and* checking the base was left alone | only while exam 11's task numbers hold |
| `helm-oci` | `--skip-crds` printing `3` CustomResourceDefinitions instead of `0`, and the chart value that actually works | only while exam 3's task numbers hold |

Record `tour` for the README and for a LinkedIn post: it shows the *grading*,
not just the questions, and "the grader checks the cluster, not your answer" is
the thing that makes this different from a list of exam questions. The two
exam-specific scripts are better as a second asset — a reply, a carousel
slide, a follow-up post.
