# Workout search follow-up

## Recovery of the original 48 misses

The archived app reproduced all 90 previous results, ordered workout IDs, extracted slots and clarification choices. The revised rules then returned the **exact gold workouts for all 48** queries that had incorrectly returned nothing. The normal hybrid also recovered all 48. Both preserved all 38 previously passing tasks, the 18 true-empty cases and both city clarifications. Across all 90 tasks, neither returned any unexpected workout IDs.

The initial revision already matched the expected workout sets. A stricter check caught semantic errors that an empty history could conceal, including treating “beyond” as an equality and extracting a state without its named city. After those fixes, the final rules passed all 90 CI checks for result membership, first-place ties, empty/clarification behavior, canonical slots and absence of extra literal terms. The simulator executed this final candidate before its binary was frozen for the fresh challenge.

This 90-query corpus is now a regression fixture. The implementer could inspect its failures. Generalization is measured separately on the new challenge.

## Fresh simulator comparison

The independent challenge contained 72 new questions and 12 new workout histories. The custodian supplied row-level judgments, acceptable first-place ties, and clarification choices before seeing candidate results. A separate SQLite oracle verified all 72 cases. The same simulator ran the archived prior binary and the frozen candidate on identical inputs and dates. The original 90-case blind release set stayed sealed.

| Search path | Exact tasks | Conversational | Simple | False empties among 53 expected matches | Model attempts | Accepted interpretations |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Previous rules | 32/72 (44.4%) | 9/47 | 23/25 | 38 | 0 | — |
| Revised rules | 34/72 (47.2%) | 11/47 | 23/25 | 36 | 0 | — |
| Revised rules with normal model routing | 35/72 (48.6%) | 12/47 | 23/25 | 36 | 40 | 17 |
| Force a model call on every query | 35/72 (48.6%) | 12/47 | 23/25 | 36 | 72 | 38 |

On this corpus, the exact eligible set and, where relevant, a valid first-ranked workout agreed with task success for every passing case. All paths kept the 16 genuine empty results and all three required city clarifications. No path returned an unexpected workout ID. The remaining misses were mostly searches that filtered out all eligible workouts. Both model paths recovered three of the 38 earlier false empties exactly; revised rules recovered two. Both model paths also converted one previously incorrect clarification into an incorrect empty result, keeping the total at 36. Neither model path lost a previously correct task.

The revised rules gained 2.8 percentage points over the old rules (two wins, zero losses, 70 ties). The paired 95% interval was 0.0 to +6.9 points. Adding normal model routing gained another 1.4 points (one win, zero losses, 71 ties; interval 0.0 to +4.2). On the conversational slice the model gained 2.1 points over the revised rules (one of 47 tasks; interval 0.0 to +6.5). Intervals use 5,000 bootstrap samples of the 12 paired scenario families. The extra 32 model calls in the forced diagnostic improved no task over normal routing.

### Where misses remain

With normal model routing, exact lookups passed 5/5, list/filter questions passed 24/48, ranked questions passed 3/16 and clarifications passed 3/3. Only 16 of the 53 questions with known matching workouts fully succeeded. Of 37 cases with numeric/date boundaries or exclusions, the extraction audit flagged 27 for the old rules, 24 for revised rules, 24 for normal model routing and 22 for forced inference. These were missing or mismatched extracted constraints; the returned rows violated zero gold predicates. Normal routing rejected 23 model responses, including nine source-span mismatches, seven invalid sport exclusions, four invalid measurements, two invalid dates, and one invalid place.

The forced lane always requested the real Apple on-device interpreter on these 72 questions. Both model paths used the original v2 instructions, typed schema, validation and fallback. The forced lane therefore measures the value of calling that production interpreter more often. It does not estimate a standalone unconstrained LLM's accuracy. No prompt or search tuning used these fresh results.

### Timing and decision

The revised rules' subsequent p50/p95 were 0.14/0.25 ms. Normal routing's final p50/p95 across subsequent queries were 2.41/5.25 s. Restricting that measurement to subsequent actual model attempts gives 4.35/5.45 s. The forced lane's subsequent p50/p95 were 4.46/5.93 s. The first model call in each lane took 4.88 s and 4.98 s, respectively, one observation each. These are test-host timings on an iOS 27.2 simulator under shared-host load. Physical-device timings require measurement on a phone.

All original 48 misses are covered by a permanent CI check. On unfamiliar questions the observed retrieval gain was much smaller. **Keep deterministic search as the default** and model-assisted interpretation as a Debug experiment. The model's measured conversational gain fell below the five-point promotion threshold, its confidence interval included zero, and protected extraction flags remain. For the next evaluation, prioritize ranking and recall on separately authored queries with multiple constraints.

The [machine-readable aggregates](followup-results.json) contain both cohorts' fingerprints, model status counts, exact recovery metrics, per-intent breakdowns, paired wins/losses/ties and timing details. The [evaluation guide](README.md) documents binary replay and the verified prior-source reconstruction.
