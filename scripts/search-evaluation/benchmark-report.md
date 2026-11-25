# Workout search benchmark, November 25, 2026

**Decision. Keep deterministic search as the default and model-assisted search as a Debug experiment.** The revised on-device prompt passed two more development tasks than the rules engine. Both passed the same 116 of 124 conversational tasks. The promotion threshold was a gain of five percentage points on conversational searches with a positive lower confidence bound. The 90-query blind set remained sealed.

## Search quality

| Split and implementation | All queries | Simple | Conversational | Macro success across intent categories | Protected cases flagged |
| --- | ---: | ---: | ---: | ---: | ---: |
| Development, legacy | 26/180 | 13/56 | 13/124 | 8.5% | No structured extraction |
| Development, rules | 170/180 | 54/56 | 116/124 | 97.2% | 0/114 |
| Development, hybrid prompt v1 | 169/180 | 55/56 | 114/124 | 97.0% | 1/114 |
| Development, hybrid prompt v2 | 172/180 | 56/56 | 116/124 | 97.6% | 0/114 |
| Independent validation, legacy | 18/90 | 5/22 | 13/68 | 9.6% | No structured extraction |
| Independent validation, frozen rules | 38/90 | 7/22 | 31/68 | 54.2% | 30/66 |

On development, the rules engine gained 80.0 percentage points over legacy, with 144 wins, zero losses, and 36 ties. On validation, the gain was 22.2 points, with 20 wins, zero losses, and 70 ties. The paired 95% intervals were +67.8 to +90.0 points for development and +13.3 to +31.1 for validation. Resampling 18 development families or nine validation families keeps near-related questions together. These samples measure synthetic English scenarios and do not estimate the frequency of real user queries.

**The validation gap is concentrated in retrieval.** Rules passed all 18 expected-empty cases and both clarification cases. They passed 18 of 70 tasks with known matching workouts, and incorrectly returned empty for 48 of those 70. All 30 protected flags were missing or mismatched extracted slots. No returned workout violated a gold predicate. Among the flagged cases, 22 wrongly returned empty, six correctly returned empty, and two returned workouts. Several queries contained more than one flagged slot. Validation was scored once on the frozen rules binary; no validation query text or labels went back to the implementer.

## What changed after measuring

1. The first rules implementation passed 166/180 with six protected development flags. Failures exposed inclusive comparison wording, a location clause running into a quantity, and ambiguous city text resolved during execution. Refining those clauses and exposing the applied location raised rules to 170/180 and cleared all six flags.
2. With those rules frozen, prompt v1 introduced two conversational regressions. In particular a date phrase could leave a possessive suffix as a literal search word, and the model could infer an extra sport from incidental wording. Other failures included rejected note clauses and conversational connecting words interpreted as search terms.
3. Prompt v2 asked for complete grammatical spans and explicit evidence for a sport. Both prompts used the same guided-generation schema, validator, rules engine, simulator, greedy sampling, 800-token cap, queries and seed. V2 gained three tasks over v1 with zero losses and 177 ties across the 180 pairs. The gain was +1.7 points with a paired 95% interval of 0.0 to +4.4 points. It removed the v1 protected flag.
4. Relative to rules, v2 had two wins, zero losses and 178 ties. Both wins were on the simple slice. On the 124 conversational pairs every success/failure outcome tied; estimated gain and both interval bounds were zero. Development provided no basis to promote the hybrid to model validation or open the blind set.

Both prompts attempted the on-device model on 18 of 180 primary queries. The other 162 were handled directly by rules. Each prompt accepted 12 interpretations and rejected six through the app validator. For v2, the rejection reasons were three invalid sort values, two invalid note values and one source-span mismatch. Remaining development losses involved connective words, scoped note lookups and superlatives. These failures motivate future independent challenge scenarios; repeated editing to maximize the current development score would provide little evidence of generalization.

## Repeats and latency

Each prompt ran three times across the same 30 development queries. Both had zero changes in applied slots, residual terms, result order, choices, action or task success across repeats. Three of those 30 cases invoked the model in each pass. This provides limited evidence about generation variability. Queries already covered by rules produced immediate results. Each prompt completed 240 hybrid observations including repeats; the three lanes together produced 600 observations per candidate.

Timings below are for v2 on an iPhone simulator running iOS 27.2 (24B8117) under shared-host load, Xcode 27.2 (27B52). Each first call has one observation. Subsequent calls ran in the same app process. The OS could retain cached assets across launches.

| Operation | First call | Subsequent p50 | Subsequent p95 | Subsequent observations |
| --- | ---: | ---: | ---: | ---: |
| Legacy result | 39.06 ms | 2.35 ms | 4.68 ms | 179 |
| Rules result | 1.00 ms | 0.20 ms | 0.52 ms | 179 |
| Hybrid final result, all routes | 4.89 ms | 0.40 ms | 1,230 ms | 239 |
| Hybrid final result, model attempted | 2,252 ms | 1,175 ms | 1,670 ms | 23 |

The repeated hybrid pass counted 24 actual model attempts. App-hosted guided generation succeeded on this simulator. Two standalone command-line probes returned inference-asset errors despite reporting model availability. The application test host therefore supplied the quality measurements. Hardware latency needs separate measurement.

## Reproduction

Run the commands in the [evaluation guide](README.md). Prompt v2 is in the source tree. To reproduce v1, use an isolated checkout of this revision and run `git apply scripts/search-evaluation/prompts/replay-v1.patch`, then build and re-run. Compare v2 with an earlier complete replay by passing `--prior-run <v1-output>` to the scorer. The [aggregate measurements](benchmark-results.json) retain SHA-256 fingerprints, paired intervals, per-intent results, explicit constraint counts, latency and regression evidence for the measured binaries. Per-query development output and private validation data stay outside the repository.
