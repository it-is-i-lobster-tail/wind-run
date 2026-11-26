# On-device workout-search tool evaluation

On the 21 fresh searches, the original filter-generating LLM had the highest exact-set score. All three paths preserved all six genuine no-match cases. All of the incorrect searches returned empty results despite available matches.

| Submitted search path | Exact workout set | Positive terrain | True no-match | Other positive | Median final search time |
| --- | ---: | ---: | ---: | ---: | ---: |
| Rules only | 12/21 | 3/9 | 6/6 | 3/6 | 0.13 ms |
| Original LLM hybrid | 14/21 | 4/9 | 6/6 | 4/6 | 884 ms |
| Tool hybrid | 12/21 | 3/9 | 6/6 | 3/6 | 2,471 ms |

Both hybrids attempted inference on 12 queries. The original interpreter accepted six interpretations. The tool hybrid invoked the real Apple tool 12 times, accepted three calls and used the original rules for nine rejected argument lists. Nine queries in each hybrid completed directly through rules. The time column includes the directly routed searches and measures the local test host on iOS Simulator 27.2. It describes submission latency on this run. Physical-device latency requires a separate measurement.

## Isolated replays

We launched the test host separately with model-assisted submission enabled and with fallback only. Both paths used the same search-session edit and submit logic as the search screen. The enabled run invoked the tool on both preselected requests. The fallback-only run made zero model requests.

| Query | Expected | Tool hybrid | Fallback only |
| --- | --- | --- | --- |
| “Which journeys on foot included a steep ascent?” | Mesa steps and Radio tower | Empty after rejected arguments | Empty |
| “Any steep ascents in Arcata?” | Empty | Empty after accepted tool call | Empty |

Two additional keyword checks ran after the comparison. “Descents” returned Fern trail with the tool enabled and returned empty with fallback only. “Climbs” returned empty in both modes despite a qualifying workout. These checks are separate from the 21-query score. Reproduce them with the `keyword-smoke` phase.

## Method and limits

The fixture defines two new synthetic histories, nine workouts and a fixed calendar. The positive terrain rows use sampled GPS routes, including a climb, a descent and an out-and-back. Noisy-flat and missing-route workouts serve as controls. Each case specifies the complete expected set before execution. No query duplicated an exact prompt in the earlier 500-runner-question study. The test host received workout data and query text. The host-side scorer compared the full set of returned IDs and the result action against the answer key.

The first build produced the same three overall scores. A subsequent validation change rejects model arguments that attribute a sport or workout type to the wrong source phrase. The table and replays use that final build. The prompt and answer key stayed fixed. These 21 hand-authored searches cover two histories and do not establish a production-wide difference in quality. Rules remain the default and on-device tool search is opt-in under Personalization.

[Fixture and expected matches](fixture.json) · [Per-query results and timings](results.json) · [Reproduction guide](../README.md)
