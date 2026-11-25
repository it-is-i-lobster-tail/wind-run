# Weekly workout search study

Ten synthetic runners supplied 1,262 workouts and five sets of search questions. Each trial asks two or three questions per runner at each of 52 Sunday checkpoints, from January 5 through December 28, 2025. That gives each runner 120 questions and each trial 1,200. The ten workout histories stay fixed across trials. Each runner's 600 query strings are distinct, although many reuse the same phrasing with a different date, city, threshold or workout type.

The simulator replay loaded the app’s compiled Debug library on ten distinct iOS simulator devices, one per runner. Its driver seeded the synthetic workouts in SwiftData, recorded generated GPS routes and exercised deterministic search against each weekly history. Timing, keyboard interaction, screen navigation and on-device model interpretation fall outside this engine replay. The [replay instructions](README.md) document the build and runner receipts.

## Final trial

The fifth build answered **634 of 1,200 questions correctly (52.83%)**. It found the exact set or an acceptable top workout for 248 of 813 positive searches (30.50%) and correctly returned empty for 386 of 387 no-match searches (99.74%). The best overall score was trial 2 at 57.50%. The separate 90-query frozen recovery suite passed on the final build.

Of the 566 final misses, 561 returned empty despite an eligible workout, two ranked the wrong workout first, two included extra workouts and one returned a match against an empty key. No response included a future workout. Runner scores ranged from 23/120 to 118/120. For example, “List runs that did not reach 4.6 kilometers as of 2025-01-05” missed two eligible runs. “Running workouts mentioning hill in Bend” missed one, and “What is the newest run in my log through 2025-01-05?” missed one.

## Grading

The grader checks the source files against the SHA-256 manifest and matches each observation to its runner's frozen query text, week, mode and expected workout IDs. A positive set query earns credit only for the complete matching set. A positive first-result query earns credit when the first workout is among the accepted IDs. A true-empty query requires an explicit empty action and zero returned workouts. Unknown, duplicate or future workout IDs invalidate the response in every mode.

## Results

| Trial | Correct / 1,200 | Accuracy | Positive sets | Positive first | True empty | First queries with accepted ties |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 415 | 34.58% | 64/790 | 0/59 | 351/351 | 21 |
| 2 | 690 | 57.50% | 245/717 | 13/51 | 432/432 | 11 |
| 3 | 648 | 54.00% | 217/732 | 64/101 | 367/367 | 11 |
| 4 | 626 | 52.17% | 225/744 | 0/55 | 401/401 | 21 |
| 5 | 634 | 52.83% | 176/697 | 72/116 | 386/387 | 12 |

Each search class shows correct answers divided by questions. Each trial used fresh query text and a new build, so changes between rows reflect both software changes and differences in the questions.

The tie column is a subset of positive first queries. It captures ambiguity explicitly represented by multiple accepted winners. A separate wording check found 43, 16, 16, 9 and 38 first-result questions in trials 1–5 that said “longest” or “shortest” without naming distance, time, pace, duration, speed or a unit such as minutes or miles. These may admit a distance or duration interpretation and receive the author's frozen grade. Other kinds of ambiguity were not enumerated.

These are generated running histories and templated questions. An example from trial 1 asks for April distance sessions lasting at least 36 minutes at a January checkpoint. Queries about future months can have an easy empty answer. The share of empty keys varies from 29.25% to 36.00% across trials. The results measure this synthetic mix, with no estimate of accuracy for real users.

## Combined-filter follow-up

Replaying the same fifth-trial questions with the revised text and comparison filters recovered 22 previously missed searches. Every previously correct response kept its grade. Correct positive responses increased from 248/813 to 270/813, correct empty responses stayed at 386/387, and overall accuracy rose from 634/1,200 (52.83%) to 656/1,200 (54.67%). The query-level grader still found 539 false empties. The earlier questions informed this change, so this is a regression replay.
