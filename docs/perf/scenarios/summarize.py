#!/usr/bin/env python3
"""Reads gate `applog` lines on stdin, keeps the `-paseo-perf` window lines after --after
("YYYYMMDD HHMMSS", the Mac's clock), prints them and one VERDICT line.
Budget (docs/perf/PERFORMANCE-RULES.md): zero hitches over 1 frame, no stall over 8 ms."""
import re, sys

after = None
if "--after" in sys.argv:
    raw = sys.argv[sys.argv.index("--after") + 1].replace(" ", "")
    after = "%s-%s-%s %s:%s:%s" % (raw[0:4], raw[4:6], raw[6:8], raw[8:10], raw[10:12], raw[12:14])

tot = dict(win=0, fr=0, hit=0, drop=0, scroll=0, stall=0)
worst = 0.0; smax = 0.0; gap = 0; busy = []
for line in sys.stdin:
    m = re.match(r"(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d)\S*\s.*?\[com\.wiselfx\.paseoclient:perf\] (perf[.\w]* .*)", line)
    if not m:
        continue
    stamp, body = m.groups()
    if after and stamp < after:
        continue
    if body.startswith("perf start"):
        continue
    print(stamp[11:] + " " + body)
    kv = dict(re.findall(r"(\w+)=(\S+)", body))
    if body.startswith("perf.hot"):
        continue
    if "fr" not in kv:
        continue
    tot["win"] += 1
    tot["fr"] += int(kv["fr"]); tot["hit"] += int(kv["hit"]); tot["drop"] += int(kv["drop"])
    tot["scroll"] += int(kv.get("scroll", 0)); tot["stall"] += int(kv["stall8"])
    worst = max(worst, float(kv["worst"])); smax = max(smax, float(kv["smax"])); gap = max(gap, int(kv["gap"]))
    busy.append(int(kv["busy"].rstrip("%")))
print("VERDICT windows=%d frames=%d hitches=%d dropped=%d longest-gap=%d worst-frame=%.1fms stalls>8ms=%d stall-max=%.1fms busy-avg=%d%% scroll-frames=%d" % (
    tot["win"], tot["fr"], tot["hit"], tot["drop"], gap, worst, tot["stall"], smax,
    (sum(busy) // len(busy)) if busy else 0, tot["scroll"]))
