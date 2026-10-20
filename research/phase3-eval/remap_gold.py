"""Re-index gold labels from the segmentation they were recorded at to a newer pipeline's.

Gold block indices follow P3-1 at 55d8701. When the pipeline changes segmentation, blocks are
matched by text between the two `fmspike render` outputs (SPIKE_SEGMENTER=ingest):

- same text: same label;
- a new block that is a piece of one old block (a split): the old block's label;
- a new block that joins several old blocks with the same label (a merge): that label;
- anything else: unmappable, written as null and left out of scoring.

    python3 remap_gold.py gold.local.json render-old.txt render-new.txt out.json

Prints counts only (no text). The output, like the gold, is gitignored.
"""

import json
import re
import sys
from pathlib import Path


def parse_render(path: str) -> dict[str, list[str]]:
    sheets: dict[str, list[str]] = {}
    name = None
    cur: list[str] | None = None
    for line in Path(path).read_text(encoding="utf-8").splitlines():
        line = line.rstrip("\n")
        if line.startswith("=== "):
            name = line[4:].strip()
            sheets[name] = []
            cur = None
        elif line.startswith("--- metadata prompt"):
            cur = None
            name = None
        elif name is not None and re.match(r"^Block \d+:", line):
            cur = []
            sheets[name].append(cur)  # type: ignore[arg-type]
        elif cur is not None:
            cur.append(line)
    return {n: ["\n".join(b).strip() for b in bs] for n, bs in sheets.items()}


def remap(old: list[str], new: list[str], labels: list) -> tuple[list, dict[str, int]]:
    stats = {"same": 0, "split": 0, "merge": 0, "unmapped": 0}
    out = []
    for t in new:
        if t in old:
            out.append(labels[old.index(t)])
            stats["same"] += 1
            continue
        host = [i for i, o in enumerate(old) if t and t in o]
        if len(host) == 1:
            out.append(labels[host[0]])
            stats["split"] += 1
            continue
        parts = [i for i, o in enumerate(old) if o and o in t]
        if parts and len({json.dumps(labels[i]) for i in parts}) == 1:
            out.append(labels[parts[0]])
            stats["merge"] += 1
            continue
        out.append(None)
        stats["unmapped"] += 1
    return out, stats


def main() -> None:
    gold_path, old_path, new_path, out_path = sys.argv[1:5]
    gold = json.loads(Path(gold_path).read_text())
    old, new = parse_render(old_path), parse_render(new_path)
    changed = 0
    total = {"same": 0, "split": 0, "merge": 0, "unmapped": 0}
    for name, g in gold.items():
        if name not in new or old.get(name) == new[name]:
            continue
        changed += 1
        g["labels"], st = remap(old[name], new[name], g["labels"])
        g["ambiguousBlocks"] = [
            i for i, l in enumerate(g["labels"]) if isinstance(l, list)
        ]
        for k, v in st.items():
            total[k] += v
    Path(out_path).write_text(json.dumps(gold, indent=1, ensure_ascii=False))
    print(
        f"pastes with changed segmentation: {changed}/{len(gold)}; blocks in them: {total}"
    )


if __name__ == "__main__":
    main()
