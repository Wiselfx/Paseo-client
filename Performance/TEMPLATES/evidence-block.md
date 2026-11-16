# Evidence block (paste into the PR description or the final message)

```text
Performance evidence
- final-check: base=<ref (sha)>  auto-failed=0  auto-pass=<n>  manual=<n ticked>  escalations=<k>   (paste the SIGN-OFF block below)
- measure: REQUIRED | not required (<one clause: which skip-list entry>)
- build: Release (install-release <branch>)  |  Debug (counts only; say why)
- script: <scenario name + gate do steps>   chat: <the test chat>   runs: 3 cold   app-start window excluded: yes
- idle floor (same build): hitches <med [min..max]>  stall max <ms>
- BEFORE (<ref/sha>): hitches <med [min..max]>  worst frame <ms>  stall8 <n>  stall max <ms>  busy <%>  body counts: <view:n>
- AFTER  (<ref/sha>): hitches <med [min..max]>  worst frame <ms>  stall8 <n>  stall max <ms>  busy <%>  body counts: <view:n>
- verdict: <better | within range | worse>; difference larger than the baseline range: yes/no
- budget (BUDGETS.md row <n>): met | not met (<which, why>)
- commit subject: W1: <what> (<before> -> <after>)
```
Rules: median and range of 3 runs, same script and chat for before and after; "within range" is a valid honest answer; do not compare Debug with Release.
Template for the findings entry: [findings-entry.md](findings-entry.md).
