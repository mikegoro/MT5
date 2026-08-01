# MikeyScalping.mq5 — audit against source video screenshots

Target EA in the video: **AXIOM 2.05** ("AXIOM GOLD PUNISHER"), XAUUSD.m, H1 chart.
Our implementation: `MikeyScalping.mq5` (TREMOR_Grid_Recovery), built from a
second-hand text spec produced by another agent from these same screenshots.

Purpose: verify (a) the intermediate spec against the visual evidence, and
(b) our code against both.

Status: **batch 1 of 38 reviewed (screenshots 1-5).** Findings provisional.

---

## Batch 1 — screenshots 1-5

### S3, S4, S5 — MT5 desktop input dialog (AXIOM 2.05)

Input panel read directly off screen, top to bottom:

| Input | Video value | Our value | Match |
|---|---|---|---|
| `=== Trade Settings ===` | separator | separator | yes |
| Initial lot size (MINIMUM) | 0.01 | 0.01 | yes |
| Distance for pending orders ($) | 0.5 | 0.5 | yes |
| Profit target in dollars | 0.5 | 0.5 | yes |
| Loss to trigger recovery ($) | 0.5 | 0.5 | yes |
| `=== Martingale Settings ===` | separator | separator | yes |
| Martingale multiplier | 2.0 | 2.0 | yes |
| Maximum recovery attempts | 3 | 3 | yes |
| Use trailing stop | true | true | yes |
| `=== Risk Management ===` | separator | separator | yes |
| Maximum simultaneous positions | 5 | 5 | yes |
| Stop loss per trade ($) | 2.0 | 2.0 | yes |
| Take profit per trade ($) | 1.0 | 1.0 | yes |
| Daily profit target ($) | 100.0 | 100.0 | yes |
| Max loss (% of balance) | 50.0 | 50.0 | yes |

**Conclusion: the intermediate spec's input block is accurate.** Every name,
order, grouping and default matches the real EA. No transcription error there.

Not yet verified: `MagicNumber` (below the visible scroll), and whether AXIOM
has any session/time inputs (none visible so far — our added `SessionStart`/
`SessionEnd` dropdowns are an addition, not something AXIOM has).

### S2 — mobile MT5, live SELL basket

Balance 12.16 / Equity 13.51 / Margin 7.23 / Free 6.28 / Level 186.86% / P/L +1.35

| # | Side | Lots | Entry | Current | P/L |
|---|---|---|---|---|---|
| 1 (newest) | sell | 0.01 | 4337.77 | 4337.78 | -0.04 |
| 2 | sell | 0.01 | 4338.03 | 4337.78 | +0.25 |
| 3 | sell | 0.01 | 4338.03 | 4337.78 | +0.25 |
| 4 | sell | 0.01 | 4338.19 | 4337.78 | +0.41 |
| 5 (oldest) | sell | 0.01 | 4338.26 | 4337.78 | +0.48 |

Sums to +1.35, matching the header. Confirms **0.01 lot = $1 per $1.00 of gold**,
which validates our `MoneyToPriceDistance()` conversion.

### S1 — mobile MT5, live BUY basket

Balance 65.86 / Equity 67.59 / Margin 10.12 / Free 57.47 / Level 667.89% / P/L +1.74

| # | Side | Lots | Entry | Current | P/L |
|---|---|---|---|---|---|
| 1 (newest) | buy | 0.01 | 4337.77 | 4337.91 | +0.14 |
| 2 | buy | 0.01 | 4337.74 | 4337.91 | +0.17 |
| 3 | buy | 0.01 | 4337.77 | 4337.91 | +0.14 |
| 4 | buy | 0.01 | 4337.84 | 4337.91 | +0.07 |
| 5 | buy | 0.01 | 4337.63 | 4337.91 | +0.28 |
| 6 (oldest) | buy | **0.02** | 4337.44 | 4337.91 | +0.94 |

Sums to +1.74, matching the header.

---

## Contradictions against our implementation

### C1 — Layers are added INTO profit, not on adverse moves  **[critical]**

S2 is the clean case. Oldest to newest, the sell entries run
4338.26 -> 4338.19 -> 4338.03 -> 4338.03 -> 4337.77: monotonically **down**.
For a short basket, falling price is *profit*. AXIOM added each new layer as the
trade moved further into the money.

S1 shows the same shape for longs — oldest entry 4337.44 is the lowest, later
entries are higher, price rising into profit.

Our `ManageEntries()` does the exact opposite:

```
if(dir > 0) adverseMoveReached = (lastEntry - ask) >= DistanceForPending;
else        adverseMoveReached = (bid - lastEntry) >= DistanceForPending;
```

We only layer when price moves **against** the basket. This is averaging down;
AXIOM is pyramiding. Directionally inverted — the single biggest gap found so far.

Note this also matches the source spec's own wording being ambiguous: it says
"whenever floating drawdown increases **or** price moves by DistanceForPending",
and the agent resolved that toward drawdown. The screenshots resolve it the
other way.

### C2 — Grid spacing is far tighter than $0.50  **[critical]**

Observed gaps between consecutive entries:

- S2 sells: 0.07, 0.16, 0.00, 0.26
- S1 buys: 0.19, 0.21, 0.07, 0.03, 0.00

Range roughly **$0.00 to $0.26**, never $0.50. Two pairs filled at *identical*
prices (4338.03 twice, 4337.77 twice), which a $0.50 distance gate could never
produce.

So `DistanceForPending = 0.5` is **not** the spacing between layers, which is how
we implemented it. Its real meaning is still unknown — candidates: distance at
which a pending order is parked from price, a floating-loss threshold, or
something unrelated to layer spacing entirely.

### C3 — Six positions with "Maximum simultaneous positions = 5"

S1 shows six open positions on one symbol. Our cap blocks strictly at 5.

Plausible reading: the cap counts **grid layers only**, with the initial entry
outside the count (1 + 5 = 6). Needs confirmation from later screenshots.

### C4 — Mixed lot sizes inside one basket

S1: one 0.02 plus five 0.01, all open simultaneously. Our code forces every layer
in a sequence to `g_cycleBaseLot`.

Strong hypothesis, fits the evidence exactly: **the initial entry uses the
martingale-scaled lot, and every subsequent grid layer uses `InitialLotSize`
(0.01) regardless of recovery level.** The 0.02 is the oldest position in the
basket — i.e. the cycle opened at recovery level 1 (0.01 x 2^1) and then layered
at the base 0.01.

If confirmed, this is a different rule from both the spec and our code.

### C5 — Baskets run well past the $0.50 profit target

`Profit target in dollars = 0.5`, yet S1 sits at **+1.74** and S2 at **+1.35**,
both still open. Individual position P/Ls (0.07 ... 0.94) show no per-trade TP at
$0.50 or $1.00 being enforced either.

Our `SyncBasketTakeProfit()` writes a hard TP that would have closed S1 at +0.50.
Something is letting these run — most likely `Use trailing stop = true` governing
the exit rather than a fixed basket TP. Mechanism not yet determined.

---

## Batch 2 — screenshots 6-10

All from the same video, ordered by the in-video timestamp badge.

| Shot | Video t | Balance | Equity | Margin | P/L | Basket |
|---|---|---|---|---|---|---|
| S9  | 4:36 | 10.00 | 10.31 | 5.78  | +0.31 | 4 buys 0.01 |
| S10 | 4:36 | 11.81 | 12.16 | 1.45  | +0.35 | 1 buy 0.01 **+ 1 sell order in flight** |
| S8  | 4:37 | 12.16 | 10.26 | 7.23  | -1.90 | 5 sells 0.01 |
| S7  | 4:38 | 18.64 | 15.95 | 7.23  | -2.69 | 5 sells 0.01 |
| S6  | 4:39 | ~28.13 | ~31.10 | 10.12 | +2.97 | 5 buys 0.01 + 1 buy **0.02** |

Account grows 10.00 -> 11.81 -> 12.16 -> 18.64 -> ~28.13 -> 65.85 (S1, 4:42)
across roughly six minutes of video.

### B2-1 — Margin arithmetic validates every lot reading

Margin per 0.01 lot is constant at ~144.6 across all five shots:

| Shot | Total lots | Margin | Margin / lot |
|---|---|---|---|
| S10 | 0.01 | 1.45  | 145.0 |
| S9  | 0.04 | 5.78  | 144.5 |
| S8  | 0.05 | 7.23  | 144.6 |
| S7  | 0.05 | 7.23  | 144.6 |
| S6  | 0.07 | 10.12 | 144.6 |
| S1  | 0.07 | 10.12 | 144.6 |

S6 and S1 both total 0.07 = five 0.01 layers + one 0.02. The 0.02 reading is
confirmed independently of the P/L column.

### B2-2 — Position list is ordered oldest-at-BOTTOM

In both S1 and S6 the 0.02 sits at the bottom of the list. Since the scaled lot
can only belong to the cycle's opening trade, bottom = oldest. This ordering is
assumed for all entry-sequence analysis below.

### B2-3 — Pyramiding confirmed (C1 upheld)

Entries oldest -> newest:

- S8 sells: 4338.26, 4338.19, 4338.03, 4338.03, 4337.74 — falling, i.e. into profit
- S7 sells: 4339.65, 4339.52, 4339.47, 4339.47, 4339.45 — falling, into profit
- S6 buys: 4338.20(0.02), 4338.38, 4338.52, 4338.52, 4338.49, 4338.60 — rising, into profit
- S1 buys: 4337.44(0.02), 4337.63, 4337.84, 4337.77, 4337.74, 4337.77 — rising, into profit
- S9 buys: 4337.39, 4337.38, 4337.19, 4337.49 — **mixed**, two layers added on an
  adverse move

Four of five baskets pyramid cleanly. S9 is the exception and is also the only
basket on the fresh 10.00 account. Not yet explained.

### B2-4 — Spacing confirmed far below $0.50 (C2 upheld)

S7 is the tightest yet: all five entries inside a **$0.20** band
(4339.45-4339.65), with two filled at the identical price 4339.47. S6 spans
$0.40 across six entries. A $0.50 distance gate cannot produce any of this.

### B2-5 — Same basket observed winning and losing

S2 (4:37, +1.35) and S8 (4:37, -1.90) are the **same five sell positions** on the
same balance of 12.16 — entries 4338.26 / 4338.19 / 4338.03 / 4338.03 / 4337.7x.
Price at 4337.78 in one and 4338.43 in the other. Useful: it shows the basket is
held through a full swing from +1.35 to -1.90 without any exit firing.

### B2-6 — Per-trade stop loss is not being hit, and is consistent with $2.00

Worst single position seen is -0.69 (S8). With `Stop loss per trade = 2.0` on
0.01 lots, a stop would sit $2.00 away, so nothing here should have triggered.
Consistent with per-trade stops existing, but does **not** prove they are attached.

### B2-7 — Baskets run far past the $0.50 profit target (C5 upheld, new hypothesis)

Open baskets observed at +1.35, +1.74, +2.97 with `Profit target in dollars = 0.5`.
No individual position sits near $0.50 or $1.00 either, so no per-trade TP is
firing.

**New leading hypothesis:** `ProfitTargetInDollars` is the threshold that *arms
the trailing stop*, not a hard basket TP. Once basket profit reaches $0.50 the
exit becomes a trailing one and the basket is allowed to run. This fits every
observation so far and is consistent with `Use trailing stop = true`.

Our `SyncBasketTakeProfit()` writes a hard broker-side TP at $0.50 and would have
closed all three of these baskets early. Very likely wrong.

### B2-8 — S10: a SELL order in flight while a BUY position is open  **[unresolved, high impact]**

S10 is the only shot showing the **Orders** section, and it contains:

```
Positions
  XAUUSD.m buy 0.01     4337.49 -> 4337.84    +0.35
Orders
  XAUUSD.m sell
  0.01 / 0 at market                          started
```

Two readings, and they imply very different architectures:

1. **Close in flight.** MT5 closes a long by sending a sell market order, which
   appears transiently in Orders. Benign — matches our model.
2. **Hedging.** The EA holds opposing positions simultaneously. This would break
   our single-direction basket model completely: `BasketStats()` assumes one
   direction and takes `dir` from the first position it finds.

Argument against (1): the buy is at +0.35, below the $0.50 target and well below
the $1.00 per-trade TP, so there is no obvious reason to close it here.
Argument against (2): no screenshot so far shows buys and sells open together.

**Must be resolved before any code change.** A screenshot showing both a buy and
a sell position open at once would settle it immediately.

---

## Batch 3 — screenshots 11-15

**S11 is a duplicate of S1** (4:42, balance 65.86, six buys, +1.74). Ignored.

### B3-1 — CORRECTION: list order is oldest-at-TOP, and B2-2 was wrong

S12 settles this and reverses two earlier conclusions.

S12 (balance 65.85, margin 7.23 = 0.05 lots) shows **five** buys:
4337.77, 4337.74, 4337.77, 4337.84, 4337.63 — all 0.01, basket at -1.25 with
price at 4337.50.

S1/S11 (balance 65.86, margin 10.12 = 0.07 lots) shows those **same five entries
plus one more at the bottom**: 0.02 at 4337.44.

Same basket, same balance, one extra row. The new position was therefore
**appended at the bottom**. Oldest is at the TOP.

B2-2 assumed the opposite, reasoning that the scaled lot had to be the opening
trade. That assumption was wrong: the 0.02 is the *newest* position, not the
oldest.

### B3-2 — CORRECTION: C1 reversed. Layers ARE added on adverse moves

With the corrected ordering, every basket re-reads as averaging into drawdown,
which is what our code already does.

S13 is the cleanest example — six sells, oldest to newest:

```
4339.11 -> 4339.10 -> 4339.15 -> 4339.18 -> 4339.21 -> 4339.38 (0.02)
```

Monotonically **rising** against a short basket. Textbook averaging up.

Re-reading the earlier baskets the same way:

- S8 sells: 4337.74 -> 4338.03 -> 4338.03 -> 4338.19 -> 4338.26 — rising, adverse
- S7 sells: 4339.45 -> 4339.47 -> 4339.47 -> 4339.52 -> 4339.65 — rising, adverse
- S1 buys: 4337.77 -> ... -> 4337.63 -> 4337.44 — falling, adverse
- S6 buys: 4338.60 -> ... -> 4338.38 -> 4338.20 — falling, adverse

**C1 is withdrawn.** `ManageEntries()` layering on adverse moves is correct.
The direction of the gate was right all along.

### B3-3 — C2 stands: spacing is still nowhere near $0.50

Corrected ordering does not rescue the spacing figure. S13 gaps, in sequence:
0.01, 0.05, 0.03, 0.03, 0.17. S7 spans $0.20 across five entries.

`DistanceForPending = 0.5` is still not the layer spacing.

### B3-4 — Lot size escalates WITHIN a basket  **[new, contradicts spec and our code]**

The newest position in a basket is repeatedly larger than the earlier ones.

| Shot | Basket composition (oldest -> newest) | Total | Margin | Check |
|---|---|---|---|---|
| S13 | 0.01 x5, then 0.02 | 0.07 | 10.12 | ok |
| S1/S11 | 0.01 x5, then 0.02 | 0.07 | 10.12 | ok |
| S6 | 0.01 x5, then 0.02 | 0.07 | 10.12 | ok |
| S15 | 0.01 x5, then 0.02, 0.02 | 0.09 | 13.01 | ok |
| S14 | 0.02 x3, then 0.03 x3 | 0.15 | 21.89 | ok |

All verified against the 144.6-margin-per-0.01-lot constant.

This directly contradicts the spec's "All grid layers within the SAME active
sequence must keep the fixed base lot size" and our `g_cycleBaseLot` behaviour.
The escalation happens **inside one open basket**, not between cycles.

Progression rule not yet determined. Two candidates:

- **Step every 5 layers**: 0.01 x5, 0.02 x5, ... Fits S13, S1, S6, S15 exactly.
  Does not fit S14 (three 0.02 then three 0.03).
- **+0.01 per step**: 0.01 -> 0.02 -> 0.03. Fits the *sizes* in all shots
  including S14, but not the run-lengths (5 vs 3).

S14 is the outlier either way, and it has no 0.01 positions at all, so its cycle
opened at 0.02 — consistent with a *between-cycle* martingale ALSO being present
on top of the within-basket escalation.

### B3-5 — Position cap of 5 is definitely not a cap on total positions

Observed simultaneously open: **6** (S1, S6, S13), **7** (S15).
`Maximum simultaneous positions = 5` does not gate total position count.

Possible readings: it caps positions at one lot size tier, or caps something
else entirely. Our hard `cnt >= MaxSimultaneousPositions` block is wrong.

### B3-6 — Drawdown tolerance

S15: balance 70.60, floating -4.58. S14: balance 33.83, floating -2.34.
Both well inside the 50%-of-balance breaker, so nothing to test it against yet.

---

## Batch 4 — screenshots 16-20

| Shot | Video t | Balance | Margin | Lots | P/L | Basket |
|---|---|---|---|---|---|---|
| S18 | 4:43 | 78.04 | 4.34  | 0.03 | +0.41 | 3 sells 0.01 |
| S19 | 4:43 | 92.49 | 7.23  | 0.05 | -1.37 | 5 sells 0.01 |
| S17 | 4:43 | 80.26 | 18.80 | 0.13 | -5.83 | buys, 0.01 x5 + 0.02 x2 visible + more hidden |
| S20 | 4:43 | 80.26 | 18.80 | 0.13 | -6.43 | same basket as S17, later |
| S16 | 4:45 | 97.89 | 21.70 | 0.15 | +3.06 | buys, mixed 0.01/0.02, **partly obscured** |

S16's position rows are behind the TikTok overlay and the play button; only the
header figures are reliable. Not used for entry-sequence analysis.

### B4-1 — S17/S20: same basket, two moments, no new positions

Identical entries, identical balance (80.26) and margin (18.80). Price moved
4336.96 -> 4336.87 and the basket deepened from -5.83 to -6.43. Margin unchanged,
so nothing was added between the two frames.

Visible entries, oldest -> newest:

```
4338.15 (0.01)
4338.14 (0.01)
4338.13 (0.01)
4337.72 (0.01)
4337.44 (0.01)
4336.98 (0.02)
4337.02 (0.02)
```

Visible P/Ls sum to -4.94 (S17) and -5.75 (S20) against headers of -5.83 and
-6.43, and visible lots total 0.09 against a margin implying 0.13. **Roughly two
more 0.02 positions are scrolled off below.** So this basket holds ~9 positions.

### B4-2 — Spacing: highly variable, and this is the key unresolved item

S17/S20 gaps between consecutive entries:

```
0.01, 0.01, 0.41, 0.28, 0.46, 0.04
```

Three of those (0.41 / 0.28 / 0.46) are in the neighbourhood of $0.50. The
others are not remotely close.

Across all baskets so far the picture is bimodal:

- **Tight cluster fills**: 0.00-0.05, sometimes at literally identical prices
  (4338.03 x2 in S8, 4339.47 x2 in S7, 4338.52 x2 in S6, 4338.72 x2 in S19)
- **Wide fills**: 0.28-0.46, only seen in S17/S20

Two mechanisms may be running at once — for example a $0.50-spaced pending
order alongside a separate market-order trigger that can fire several times in
quick succession. A single distance gate of any value cannot produce both
patterns.

`DistanceForPending` remains unexplained. This is now the biggest open item.

### B4-3 — Within-basket lot escalation confirmed again

S17/S20: five 0.01 then 0.02, 0.02 (plus ~two more 0.02 hidden). Same shape as
S15. B3-4 stands.

### B4-4 — Small baskets exist

S18 has only three positions, all 0.01, total 0.03 lots (margin 4.34 confirms).
So baskets are not always driven to 5+; some resolve early.

### B4-5 — Methodological note: the red badge is video playback position

Balances across shots run 10.00 -> 11.81 -> 12.16 -> 18.64 -> ~28 -> 33.83 ->
56.15 -> 65.85 -> 70.60 -> 78.04 -> 80.26 -> 92.49 -> 97.89 while the badge only
advances 4:36 -> 4:45.

That badge is the **TikTok playback position**, not elapsed market time. The
clips are non-contiguous and may be days apart. Consequence: balance deltas
between shots cannot be used to infer per-basket profit, and the apparent
"$10 to $98 in nine minutes" is an artefact of editing, not a measurement.

Only shots sharing identical entry prices, balance and margin (S1/S11/S12,
S2/S8, S17/S20) can be treated as temporally adjacent.

---

## Batch 5 — screenshots 21-25

| Shot | Video t | Balance | Margin | Lots | P/L | Basket |
|---|---|---|---|---|---|---|
| S22 | 4:46 | 134.88 | 2.89  | 0.02 | -0.40  | 2 sells 0.01 |
| S21 | 4:46 | 134.88 | 10.12 | 0.07 | +3.71  | 6 sells, same basket as S22 grown |
| S24 | 4:45 | 97.89  | 21.70 | 0.15 | +3.96  | buys, same basket as S16 |
| S23 | 4:46 | 117.12 | 47.70 | 0.33 | +14.71 | buys, many rows hidden |
| S25 | 4:49 | 166.14 | 39.04 | 0.27 | -4.11  | sells, many rows hidden |

S22 -> S21 is a third sequential pair: identical balance, and S22's two entries
(4336.67, 4336.69) are the **top two rows** of S21's six. Confirms B3-1 again —
oldest at top, new positions appended below.

### B5-1 — THE LOT TIER RULE  **[solved]**

Margin / 144.6 gives exact total lots, which lets the scrolled-off rows be
reconstructed. One rule fits **every basket across all 25 screenshots**:

> Positions are opened in tiers of **5**. Tier 1 uses 0.01, tier 2 uses 0.02,
> tier 3 uses 0.03. Lot size steps up only after 5 positions exist at the
> current size.

| Shot | Total lots | Decomposition | Positions |
|---|---|---|---|
| S10 | 0.01 | 1 x 0.01 | 1 |
| S22 | 0.02 | 2 x 0.01 | 2 |
| S18 | 0.03 | 3 x 0.01 | 3 |
| S9  | 0.04 | 4 x 0.01 | 4 |
| S19, S2, S7, S8, S12 | 0.05 | 5 x 0.01 | 5 |
| S1, S6, S11, S13, S21 | 0.07 | 5 x 0.01 + 1 x 0.02 | 6 |
| S15 | 0.09 | 5 x 0.01 + 2 x 0.02 | 7 |
| S17, S20 | 0.13 | 5 x 0.01 + 4 x 0.02 | 9 |
| S16, S24 | 0.15 | 5 x 0.01 + 5 x 0.02 | 10 |
| S25 | 0.27 | 5 x 0.01 + 5 x 0.02 + 4 x 0.03 | 14 |
| S23 | 0.33 | 5 x 0.01 + 5 x 0.02 + 6 x 0.03 | 16 (tier 3 over-full, see below) |

Every value is consistent. S23 is the only one needing a 6th position in a tier,
and its margin reading (47.70) is the least precise of the set.

**This explains `Maximum simultaneous positions = 5`.** It is not a cap on total
positions — it is the number of positions held **per lot tier** before the size
steps up. Our hard block at 5 total positions is wrong.

**The tier progression is LINEAR, not exponential**: 0.01 -> 0.02 -> 0.03.
S14 shows literal "0.03" rows on screen, so the third tier really is 0.03 and
not 0.04. `MartingaleMultiplier = 2.0` therefore does **not** drive the
within-basket escalation. Its role is still unaccounted for.

### B5-2 — Layer spacing is almost certainly TIME-based, not price-based

S24 forces this conclusion. Its buys, oldest -> newest:

```
4338.07 -> 4338.51 -> 4338.76 -> 4338.81 -> 4339.13 -> 4339.10 -> 4339.31
```

Rising against a **long** basket — i.e. layers added as the trade moved into
profit. But S17/S20 buys fall steadily (adverse), and S13/S8/S7 sells rise
steadily (adverse).

So layering happens in **both** directions depending on the basket. Combined
with observed gaps ranging from 0.00 to 0.74 with no clustering at any value,
no price-distance gate of any size can reproduce this.

A fixed **time interval** explains everything: layers appear at whatever price
happens to be current when the timer fires. Quiet market -> near-identical fill
prices (the repeated duplicate entries seen in S6, S7, S8, S19). Fast market ->
gaps of 0.4-0.7.

**Both our implementation and the source spec are wrong here.** We gate on an
adverse move of `DistanceForPending`; the EA appears not to gate on price at all.

### B5-3 — The hedging question (B2-8) is resolved: no hedging required

S23 and S25 both show all-visible-rows losing while total P/L is far better
(+14.71 and -4.11 against visible sums of about -5.5 and -12.9). That looked
like it needed opposing positions.

It does not. The hidden rows are simply **later layers further along the adverse
move**, which are profitable after a partial retrace:

- S25: visible sells 4335.24-4336.29, price 4337.75. Hidden sells entered near
  4338.2+ as price rose are now in profit. 0.18 hidden lots at ~+$0.49 average
  gives the +8.78 needed.
- S23: visible buys 4336.82-4337.88, price 4336.61. Hidden buys entered near
  4335.8 as price fell are now in profit. 0.25 hidden lots at ~+$0.81 gives the
  +20.25 needed.

Consistent single-direction baskets throughout. **B2-8 downgraded** — the sell
order in S10 was most likely a close in flight, not a hedge.

### B5-4 — Basket sizes are much larger than modelled

Reconstructed position counts reach **14 (S25)** and **~16 (S23)**, with total
exposure up to 0.33 lots on a $117 account. Margin level in S23 is down to 276%.

Our `MaxSimultaneousPositions` block caps at 5. Off by a factor of three.

---

## Batch 6 — screenshots 26-30

| Shot | Video t | Balance | Margin | Lots | P/L | Dir |
|---|---|---|---|---|---|---|
| S28 | 4:52 | 196.73 | 30.36 | 0.21 | +11.40 | buy |
| S27 | 4:52 | 213.67 | 21.69 | 0.15 | +1.27  | sell |
| S26 | 4:53 | 224.07 | 56.37 | 0.39 | +7.77  | buy |
| S30 | 4:55 | 243.62 | 13.01 | 0.09 | +5.55  | sell |
| S29 | 4:55 | 254.59 | 30.34 | 0.21 | +4.54  | buy |

### B6-1 — S30 is a complete basket with nothing hidden: method validated

S30's seven visible rows sum to **exactly +5.55**, matching the header to the
cent, and margin 13.01 gives exactly 0.09 lots = 5 x 0.01 + 2 x 0.02.

This is the first basket where the visible rows are provably the whole basket.
It confirms the reconstruction technique used throughout: margin / 144.6 = total
lots, and any shortfall against the header P/L is scrolled-off rows.

### B6-2 — Tier rule (B5-1) holds on four of five

| Shot | Lots | Decomposition | Positions |
|---|---|---|---|
| S30 | 0.09 | 5 x 0.01 + 2 x 0.02 | 7 |
| S27 | 0.15 | 5 x 0.01 + 5 x 0.02 | 10 |
| S28 | 0.21 | 5 x 0.01 + 5 x 0.02 + 2 x 0.03 | 12 |
| S29 | 0.21 | 5 x 0.01 + 5 x 0.02 + 2 x 0.03 | 12 |
| S26 | 0.39 | **does not decompose cleanly** | ~17 |

S26 is the one exception. 0.39 leaves 0.09 after three full tiers
(0.05 + 0.10 + 0.15 = 0.30), which is not divisible by a 0.04 fourth tier.
Either the margin reading is imprecise, tier 3 runs past 5 positions, or a
position survived from an earlier cycle. Flagged, not resolved.

### B6-3 — Gap distribution across all baskets supports the timer hypothesis

Every consecutive-entry gap measured so far, in price units:

```
0.00 0.01 0.01 0.01 0.01 0.01 0.02 0.02 0.02 0.02 0.02 0.02 0.03 0.03 0.03
0.04 0.05 0.05 0.05 0.05 0.06 0.06 0.06 0.07 0.08 0.09 0.09 0.10 0.11 0.14
0.16 0.16 0.17 0.17 0.17 0.20 0.21 0.21 0.21 0.23 0.23 0.23 0.24 0.25 0.26
0.26 0.27 0.28 0.30 0.32 0.34 0.41 0.44 0.46 0.50 0.53 0.62 0.69 0.74
```

Heavily skewed toward small values with a long tail to 0.74. **No mode at 0.50**
and no cutoff anywhere. This is the shape you get from sampling price movement
over a fixed time interval, not from a distance trigger — a distance gate of X
would produce a hard floor at X and a tight cluster just above it.

S30 does contain one gap of exactly 0.50 (4336.68 -> 4337.18), but it sits
among gaps of 0.27, 0.10, 0.01, 0.17 and 0.23 in the same basket. Coincidence.

**B5-2 upheld and strengthened.**

### B6-4 — Layering direction remains mixed

- S27 sells 4338.27 -> 4338.60 -> 4339.24: rising, adverse
- S29 buys 4335.40 -> 4334.52 -> 4334.57: falling, adverse
- S30 sells 4336.41 -> 4337.28 -> 4337.67: rising, adverse
- S28 buys 4337.95 -> 4338.00 -> 4337.66 -> 4337.74 -> 4337.53: **mixed**

Direction-agnostic layering, consistent with a timer. Adverse is the common case
simply because a basket that moves favourably tends to close before it can
accumulate many layers.

---

## Batch 7 — screenshots 31-33 (final)

| Shot | Video t | Balance | Margin | Lots | P/L | Dir |
|---|---|---|---|---|---|---|
| S33 | 4:56 | 268.52 | 15.90 | 0.11 | +8.61  | sell |
| S31 | 4:59 | 315.51 | 26.01 | 0.18 | +10.47 | sell |
| S32 | 4:59 | 313.63 | 7.22  | 0.05 | +2.38  | sell |

### B7-1 — Tier rule fits all three

| Shot | Lots | Decomposition | Positions |
|---|---|---|---|
| S32 | 0.05 | 5 x 0.01 | 5 (complete, sums exactly to +2.38) |
| S33 | 0.11 | 5 x 0.01 + 3 x 0.02 | 8 |
| S31 | 0.18 | 5 x 0.01 + 5 x 0.02 + 1 x 0.03 | 11 |

S32 is a second provably-complete basket (visible rows sum exactly to header).

**Final tally: the tier rule fits 13 of 14 reconstructable baskets.** Only S26
(0.39 lots) fails to decompose.

### B7-2 — Largest gap yet: 1.47

S33 sells, oldest -> newest:

```
4335.14 -> 4334.55 -> 4334.57 -> 4336.04 -> 4335.97 -> 4336.18 -> 4336.28
```

Gaps: 0.59, 0.02, **1.47**, 0.07, 0.21, 0.10 — and the sequence reverses
direction three times. A $0.50 distance gate is conclusively ruled out.

---

# CONSOLIDATED VERDICT — all 38 images (32 distinct)

## Confirmed correct in our code

- **All 14 inputs.** Names, order, grouping, defaults all match AXIOM 2.05's
  dialog exactly (S3/S4/S5). The intermediate spec's input block is flawless.
- **Single-direction baskets.** No basket ever mixes buys and sells.
- **Dollar-to-price conversion.** 0.01 lot = $1 per $1.00 of gold, verified
  against 14 baskets' P/L columns and the constant 144.6 margin per 0.01 lot.

## Confirmed WRONG in our code (4 findings)

| # | Our code | What the video shows |
|---|---|---|
| 1 | `cnt >= MaxSimultaneousPositions` caps the basket at 5 positions | 5 is the count **per lot tier**. Observed baskets: 7, 8, 9, 10, 11, 12, 14, ~17 positions |
| 2 | Every layer uses `g_cycleBaseLot` (fixed per cycle) | Lot escalates **inside** the basket: 0.01 x5, then 0.02 x5, then 0.03 x5. Linear, not x2 |
| 3 | Layer opens on an adverse move of `DistanceForPending` ($0.50) | Gaps range 0.00 to 1.47 with no floor and no mode; layering occurs in both directions. Consistent with a **fixed time interval**, not a price gate |
| 4 | `SyncBasketTakeProfit()` writes a hard basket TP at $0.50 | Baskets observed open at +1.35, +3.71, +5.55, +8.61, +10.47, +14.71. No TP at $0.50 or $1.00 ever fires |

## No evidence either way — 7 of 14 inputs are unverified

Nothing in 32 screenshots shows a cycle opening, a basket closing, or a
stop/target being hit. The mobile position list never displays SL/TP columns,
and no History tab was ever captured.

Unverified: `DistanceForPending`, `LossToTriggerRecovery`, `MartingaleMultiplier`,
`MaxRecoveryAttempts`, `StopLossPerTrade`, `TakeProfitPerTrade`,
`DailyProfitTarget`, `MaxLossPercentOfBalance`.

In particular **the entire recovery/martingale mechanism — the thing the EA is
named for — was never observed.** `MartingaleMultiplier = 2.0` cannot be the
within-basket escalator, since tiers step 0.01 -> 0.02 -> 0.03. Its actual role
is unknown.

Also unknown: **what opens a cycle and what picks its direction.** Our
last-closed-bar rule remains a pure invention with zero supporting evidence.

## ONE observed exit — recovered from balance arithmetic

S10 -> S8 is an actual close, missed on first pass.

```
S10  balance 11.81   equity 12.16   1 buy 0.01 @ 4337.49 -> 4337.84  = +0.35
                                    Orders: sell 0.01 at market, "started"
S8   balance 12.16
```

11.81 + 0.35 = 12.16 exactly. The in-flight sell order in S10 was the close, and
the position exited at **+$0.35**.

That is **below** `ProfitTargetInDollars` (0.50) and far below
`TakeProfitPerTrade` (1.00), so neither is the exit trigger for a single
position. A trailing stop armed at some higher price and hit on a retrace fits;
so does a time-based exit. One sample cannot distinguish them.

Also relevant: **no basket was ever observed shrinking.** Across 32 shots,
baskets only ever gain positions (S22->S21, S12->S1). Weak evidence that exits
close the whole basket at once rather than leg by leg.

## Recommended changes, in order of confidence

1. **Remove the 5-position cap; make 5 the per-tier count.** High confidence,
   13/14 baskets support it.
2. **Move lot escalation inside the basket, linear by tier**
   `lot = InitialLotSize * ceil(layerIndex / MaxSimultaneousPositions)`.
   High confidence.
3. **Replace the distance gate with a time interval.** High confidence that the
   distance gate is wrong; the interval length itself is unmeasurable from these
   images and would need to be an input.
4. **Stop writing a hard basket TP at `ProfitTargetInDollars`.** High confidence
   it is wrong; what replaces it is unknown.

Items 1 and 2 are safe to implement now. Item 3 needs a value we do not have.
Item 4 removes an exit without knowing the real one, which would leave baskets
with no defined exit at all — do not implement in isolation.


1. What triggers the **first** entry of a cycle, and its direction? (still unknown)
2. What does `DistanceForPending` actually control?
3. Are SL/TP attached per position? (mobile list doesn't show these columns —
   need a desktop Trade tab or an order detail view)
4. Does the basket close all at once on one timestamp, or leg by leg?
5. Confirm the 1 + 5 = 6 position-cap reading
6. Confirm the "initial = scaled lot, layers = 0.01" hypothesis
7. Does AXIOM have any session/time filter inputs?
8. `MagicNumber` value

## Caveat on the source material

S1 and S2 are TikTok posts tagged "Creator labeled as AI-generated", captioned
"FROM 10$ TO 350$ EASY MONEY". The MT5 panels themselves look like genuine
screen captures and the arithmetic is internally consistent (position P/Ls sum
to the stated totals), so they are usable as evidence of *EA behaviour*. The
performance claims around them are marketing and carry no weight.
