# Independent grading of workout search

Search answered **305 of 500 questions correctly (61.0%)** across ten synthetic runners. It returned no workouts for 186 questions whose answers included at least one workout. These false empties account for 95.4% of the 195 failures.

| Measure | Correct | Rate |
| --- | ---: | ---: |
| Complete result set, order ignored | 269 / 434 | 62.0% |
| First result matches an accepted ID, including ties | 36 / 66 | 54.5% |
| Questions with at least one expected workout | 270 / 464 | 58.2% |
| Questions with no expected workouts | 35 / 36 | 97.2% |
| Questions asking for a recorded terrain or route profile | 1 / 50 | 2.0% |

Each of the 500 logged prompts, modes and expected ID lists matched its runner's frozen answer key. The grader evaluated each returned ID within that runner's history. The ten runner scores, in order, were 32, 31, 37, 32, 30, 27, 30, 29, 29 and 28 out of 50.

## What the misses looked like

- **Empty results.** Search returned an empty list on 221 questions. Only 35 of those empties were correct. For example, 01-12 asked for runs between 8 and 10 km inclusive and returned none of the ten qualifying workouts.
- **Wrong results.** Nine failures displayed workouts. Four had the wrong first result. Three set answers included extra workouts, one substituted a wrong workout and one returned workouts for a true no-match. For 03-22, “Find my long runs” returned all 30 runs for a key of four named long runs. For 07-41, the only result for the marathon race was the first post-race jog. For 09-50, the history contained a half marathon, and a search for the marathon race returned that half marathon and its recovery jog.
- **Terrain.** All 50 questions asking for a route profile returned empty. The 49 with qualifying workouts all failed. The sole pass was 08-44, “Find climbs in Portland,” where the runner had none. This subset covers terrain and route shape, including out-and-back and unknown routes. It excludes named workout lookups such as “Show my Sellwood out and back runs.” The authors asked **zero standalone single-word searches** in all 500 questions, so bare-term performance is measured separately below.

## Separate single-word controls

Each history received three additional queries. I reconstructed their expected sets from all 353 fixture records using the listed profile labels, then checked both the logged keys and returned IDs. **All 30 controls returned their exact expected sets.** These additional trials are outside the 500-question score.

| Literal query | Qualifying fixture profiles | Histories with exact results | Workouts returned across histories |
| --- | --- | ---: | ---: |
| `hills` | Climb, descent, out-and-back | 10 / 10 | 62 |
| `uphill` | Climb, out-and-back | 10 / 10 | 53 |
| `downhill` | Descent, out-and-back | 10 / 10 | 38 |

Runner 07 illustrates the wording difference. The literal `downhill` query returned all four qualifying workouts, including the descent labeled f5. “Find the recorded downhill run” (07-25) requested that specific descent and returned nothing. The literal `uphill` query likewise returned the climb c4 among four qualifying workouts. “Find my recorded uphill climb” (07-24) returned nothing. The sentence queries have narrower keys, but each target was retrievable with the corresponding single word.

## Answer-key and wording checks

I independently recomputed five answers per runner from the histories, covering a July date filter, a longest-distance ranking, a rolling or climb profile, a no-match query and a rain reference. Of those 50 keys, 46 agreed. Four rain keys included a total of five workouts solely because “training” contains “rain”. Question 01-35 included a25, 05-32 included R24, 07-34 included d5 and d6, and 10-27 included R10-20. All four queries returned empty despite genuine rain matches, so correcting those five IDs would leave the overall score at 305/500. A separate check of all 57 first-result questions asking for an extremum or chronological ranking found agreement with every key. The other nine first-result questions asked for a particular workout.

Some wording permits more than one reasonable interpretation. For 01-19, “recorded on flat routes” accepts 17 records labeled flat and excludes a noisy-flat record. For 03-22, “long runs” accepts four workouts named as long runs and excludes a 21.1 km half marathon. The published scores retain the authors' original choices.

The 353 workouts span June through November 2025, with 296 in Oregon and 57 in Washington. There are 446 distinct prompt texts across the 500 entries. The percentages describe this regional synthetic corpus and its repeated question patterns.
