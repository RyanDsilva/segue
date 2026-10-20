"""Aggregate a bake-off folder into one row per model (aggregates only: no song names or text).

python3 bakeoff_table.py --gold gold.local.json results/bakeoff-<ref>[-tag] [--json]
"""

import json
import re
import sys
from pathlib import Path

gold = sys.argv[sys.argv.index("--gold") + 1]
folder = Path([a for a in sys.argv[1:] if a.startswith(("/", "results"))][-1])
as_json = "--json" in sys.argv
spikes = Path(__file__).resolve().parent.parent / "phase3-spikes"
sys.path.insert(0, str(spikes))
sys.argv = ["score.py", "--gold", gold, "--skip-meta"]
import os

os.chdir(spikes)
import score

ingest = json.loads((folder / "ingest.json").read_text())
rows = []
for f in sorted(folder.glob("*.jsonl")):
    name = f.stem.removeprefix("mlx-")
    try:
        r = score.score_pipeline(str(f), ingest)
    except (KeyError, IndexError, ValueError) as e:  # incomplete run
        print(name, "unscorable:", type(e).__name__, e, file=sys.stderr)
        continue
    s = score.summarize_pipeline(r)
    log = (
        (folder / (f.stem + ".log")).read_text()
        if (folder / (f.stem + ".log")).exists()
        else ""
    )
    load = re.search(r"loaded \S+ in (\d+) ms, footprint (\d+) MB", log)
    fin = re.search(r"mlx peak (\d+) MB, peak footprint (\d+) MB", log)
    warm = re.search(r"^warmup \w+ (\d+) ms", log, re.MULTILINE)
    a, en, hi = s["all"], s["en"], s["hi"]
    if not a:  # run just started
        continue
    rows.append(
        dict(  # noqa: C408
            model=name,
            songs=a["songs"],
            blocks=a["blocks"],
            labelAcc=a["labelAcc"],
            en=en.get("labelAcc"),
            hi=hi.get("labelAcc"),
            unheaded=a["unheadedAcc"],
            unheadedN=a["unheadedN"],
            unheadedUnambig=a["unheadedUnambig"],
            hiUnheaded=hi.get("unheadedAcc"),
            perfectSongs=a["songsAllLabelsRight"],
            titleArtist=a["titleArtistOk"],
            key=a["keyOk"],
            labelFail=a["labelCallFailures"],
            metaFail=a["metaCallFailures"],
            retries=a["retries"],
            labelsP50=a["labelsP50"],
            labelsP90=a["labelsP90"],
            songP50=a["perSongP50"],
            songP90=a["perSongP90"],
            loadMs=int(load.group(1)) if load else None,
            warmupMs=int(warm.group(1)) if warm else None,
            mlxPeakMB=int(fin.group(1)) if fin else a["peakMB"],
            peakFootprintMB=int(fin.group(2)) if fin else None,
        )
    )
if as_json:
    print(json.dumps(rows, indent=1))
else:
    cols = list(rows[0]) if rows else []
    print("| " + " | ".join(cols) + " |")
    print("|" + "---|" * len(cols))
    for r in rows:
        print("| " + " | ".join("" if r[c] is None else str(r[c]) for c in cols) + " |")
