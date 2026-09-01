# Interview Preparation

*Personal notes — not part of the technical documentation.*

## The 90-second opening

> I built a player valuation system for IPL franchises using ball-by-ball data
> from 2008 to 2024 — about 260,000 deliveries.
>
> The problem: auction prices are set by reputation and bidding dynamics, but raw
> statistics can't tell you whether a player is worth their price, because they
> ignore context. A strike rate of 140 is elite in the powerplay and below
> average at the death.
>
> So I built context-adjusted metrics. The core one is Runs Added Above Average —
> how many runs a player generated compared to a league-average player off the
> same balls, in the same phase, in the same season. Same idea for bowlers using
> economy, which gives both a common unit of runs so all-rounders sit on one scale.
>
> Divide that impact by auction price and you get value per crore, which is what
> stakeholders actually care about.
>
> The finding was that around 30% of auction spend goes to players producing
> below-average impact, and death-overs specialists are systematically underpriced.
>
> PostgreSQL for the modelling — star schema, window functions, materialised
> views. Power BI for the front end. The signature visual is a quadrant chart with
> price on one axis and impact on the other, so overpaid and underpriced players
> are visible in a single glance.

**Rehearse out loud. Time it. Ninety seconds.**

---

## Anticipated questions

**Why a star schema instead of one flat table?**
Performance and maintainability. The flat file repeats team, venue and date on
all 260,000 rows. Splitting dimensions out cuts storage, makes join keys narrow
integers that index well, and means a player attribute change is one row instead
of thousands. It also maps directly onto Power BI, which is built for star
schemas — a flat table forces DAX gymnastics.

**Walk me through your hardest query.**
The gaps-and-islands streak detector. Number every innings for a player, then
number only the good innings separately. Across any run of consecutive good
innings the difference between those two numbers is constant, and it jumps the
moment the streak breaks — so grouping on the difference collapses each streak to
one row. I chose it over a recursive CTE because the recursive version walks row
by row, whereas this is two window functions and a GROUP BY: fully set-based.

**How did you handle data quality?**
Three specific problems. Player names were inconsistent across seasons, which
would have split single careers into multiple players — solved with a
normalisation function plus a manual override map. Rain-affected matches have
short innings; I flagged rather than dropped them, because dropping would bias
against players at high-rainfall venues. Auction data was patchy before 2018, so
I scoped that analysis to 2018+ and stated it on the dashboard.

**How do you know the metric is right?**
Three ways. Reconciliation — season totals checked against published IPL records.
Face validity — the top of the death-overs impact list should be names any cricket
follower recognises as finishers; when it wasn't, I found a real bug in the
required-run-rate calculation. And minimum sample thresholds so noise can't top a
leaderboard.

**Tell me about a bug you found.**
The Pressure Index. I was computing required run rate from the score *after* each
ball, which meant the runs the batter had just scored were already subtracted
from the target. That deflated apparent pressure on exactly the deliveries where
they scored, quietly inflating every finisher. Fixed with a `LAG` on the running
total. Two days to find, one line to fix.

**What are the limitations?**
No venue or pitch adjustment, so players at high-scoring grounds are flattered.
No opposition-quality adjustment. No fielding data. And the squad builder is a
greedy heuristic — squad selection is a constrained knapsack problem and greedy
doesn't solve knapsack optimally. I chose to be transparent about that rather
than present it as optimal.

**Why should a franchise trust this over their scouts?**
They shouldn't — they should use it alongside them. It's a screening tool that
narrows 600 auction players to a 40-player shortlist so scouts spend time where
it matters. The model catches market inefficiencies human judgement misses;
human judgement catches injury history and dressing-room fit that data misses.

**How would this scale to 100 million rows?**
Partition `fact_ball` by season. Move the heavy aggregations into a scheduled ELT
job writing summary tables rather than computing at query time. Consider a
columnar store — these are analytical scans over a few columns, which is exactly
what column stores are built for.

**How would you extend it?**
Venue and opposition adjustments first. Then a win-probability model so I'm
measuring contribution to *winning* rather than to runs. Then a forward-looking
projection with ageing curves, since franchises buy future performance.

---

## Making it a conversation

- **Ask them something.** "Do you follow cricket at all?" changes the register
  entirely. Either answer gives you a better version of the explanation.
- **Offer a choice.** "I can walk through the data model or jump to the insight —
  which is more useful?" This is what consultants do and it reads as confident.
- **Plant a hook.** Mention "the required run rate bug that took two days" without
  explaining it. They almost always ask, and then you're telling a debugging
  story, which is far more memorable than a feature list.
- **Have an opinion.** "The biggest inefficiency is that franchises pay for strike
  rate without asking *when* those runs came." Opinions invite disagreement, and
  disagreement is interaction.
- **Admit one redo.** "I'd build the venue adjustment from day one instead of
  bolting it on." Self-critique is the fastest route to seeming senior.

## Final checklist

- [ ] README opens with the question and a screenshot
- [ ] `EXPLAIN ANALYZE` numbers recorded in methodology.md
- [ ] Can write the gaps-and-islands query on a whiteboard from memory
- [ ] 90-second pitch rehearsed and timed
- [ ] One headline number memorised
- [ ] 3-minute walkthrough video linked in the README
- [ ] Explained it once to someone who knows nothing about cricket
