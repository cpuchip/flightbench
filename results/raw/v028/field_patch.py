# Applied INSIDE the container before the launcher starts: the image's launcher (pr43-6869c80) predates fork commit
# 0e95195 and its SPEC_CFG line carries no draft_sample_method, so the engine runs the default the fork's issue 73 calls
# wrong; the shipped default and every chain of 2026-09-05 set "probabilistic". Same edit as the chains' FIELD sed,
# written without shell escapes (the launcher's line contains backslash-escaped quotes).
import sys
p = "/app/single-user/start_qwen.sh"
s = open(p, encoding="utf-8").read()
q = chr(92) + chr(34)  # the two characters backslash, double-quote as they sit in the launcher
old = q + "num_speculative_tokens" + q + ":$DRAFT_TOKENS}"
new = q + "num_speculative_tokens" + q + ":$DRAFT_TOKENS," + q + "draft_sample_method" + q + ":" + q + "probabilistic" + q + "}"
if s.count(old) != 1:
    print("FIELD not applied: anchor count", s.count(old)); sys.exit(0 if "draft_sample_method" in s else 1)
open(p, "w", encoding="utf-8").write(s.replace(old, new))
print("FIELD applied: draft_sample_method=probabilistic on the dflash SPEC_CFG line")
