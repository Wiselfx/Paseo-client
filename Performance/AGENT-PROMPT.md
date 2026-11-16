# AGENT-PROMPT: paste this block into any task prompt for a small agent

```text
PERFORMANCE REQUIREMENT (applies to every change in Packages/PaseoUI, Packages/PaseoCore or App/)
Intent: the app must feel instant. Idle is silent, scrolling and typing never hitch, and the main thread never works more than 8 ms in one go.
Keep Performance/MUST.md open while you write code (section B = what you MUST / MUST NOT do; section A = the numbers). Do not guess:
if Performance/DECISION-TREES.md has an entry for what you are adding, follow it step by step.
Before you report done, in this order:
1. Commit or stage your work, then run: Performance/scripts/final-check.sh
2. Block 2 (AUTO-FAILED) must be empty. Fix each hit with the PATTERNS file it names. If a hit is wrong or you cannot fix it: ESCALATE, do not waive.
3. Block 3 (MANUAL) lists the MUST items the script cannot check. Answer each yes/no from your diff; on "no" or "unsure" do what the item says.
4. If the last line says "measure: REQUIRED", follow Performance/MEASURE.md and paste the evidence block (Performance/TEMPLATES/evidence-block.md).
   If you cannot run the gate, say so; never invent numbers.
5. Re-read MUST.md section A and D. Anything in section D (visible behaviour change, unbounded structure, baseline increase, transcript/composer/shell/keyboard
   code beyond a listed pattern, removing a check) is not your decision: write ESCALATE and stop.
Paste into your final message: the SIGN-OFF block with every line ticked [x] plus one clause why (or ESCALATE: why), and the line
"VERDICT: DONE (auto-failed=0, manual=N ticked, escalations=K)". Do not claim a check passed unless you ran it.
```
Procedure and decision tables: [FINAL-CHECK.md](FINAL-CHECK.md).
