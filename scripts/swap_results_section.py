"""Replace one '## ' section of results/RESULTS.md with the contents of a file (the section is identified by
its exact heading line). The old section is kept in results/raw/superseded/ with a timestamp.

  python scripts/swap_results_section.py "## v6: the mission (2026-09-02)" path/to/new-section.md
"""
import os, sys, time
sys.stdout.reconfigure(encoding="utf-8")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
p = os.path.join(ROOT, "results", "RESULTS.md")
heading, newf = sys.argv[1], sys.argv[2]
s = open(p, encoding="utf-8").read()
i = s.index("\n" + heading + "\n")
j = s.find("\n## ", i + 1)
j = len(s) if j < 0 else j
old = s[i:j]
os.makedirs(os.path.join(ROOT, "results", "raw", "superseded"), exist_ok=True)
keep = os.path.join(ROOT, "results", "raw", "superseded", f"{time.strftime('%Y%m%d-%H%M%S')}-{heading[3:20].strip().replace(' ', '_').replace(':', '')}.md")
open(keep, "w", encoding="utf-8").write(old)
new = open(newf, encoding="utf-8").read()
if not new.startswith("\n"):
    new = "\n" + new
s = s[:i] + new.rstrip("\n") + "\n" + s[j:]
open(p, "w", encoding="utf-8", newline="\n").write(s)
print("swapped:", heading, "| old kept at", os.path.relpath(keep, ROOT), "| em-dashes in new:", new.count("—"))
