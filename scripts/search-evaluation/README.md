# Workout search evaluation

Use the WindRun scheme on an iPhone simulator. Workout history uses deterministic search by default. Settings → Personalization → Use Apple Intelligence for search enables on-device tool calling when the user submits a query. Debug launches can force the hybrid on with `-workoutSearchModel` or force rules only with `-workoutSearchRulesOnly`. The existing `hybrid` benchmark lane retains the original filter-generating interpreter as a comparison. Both model paths receive the query text. The read-only `searchWorkouts` tool returns a match count or a clarification signal to the model. Workout IDs, notes, addresses and route samples stay in the search engine.

The [tool-calling study](tool-study/report.md) compares the original interpreter, the tool-enabled submission path and rules alone on fresh fixtures, then replays two cases in separate simulator runs with each setting. To reproduce, run `tool_study.py` with `--configuration <built.xctestrun> --destination <simulator-id> --output <new-directory>` and a `--phase` of `comparison`, `hybrid-replay` or `fallback-replay`.


See the [measured benchmark results](benchmark-report.md) for the development prompt comparison and independent validation.

## Follow-up audit

The [follow-up results](followup-report.md) cover the original 48 unexpected empty results and a new independently authored challenge. V1 validation is now a public regression set. The v1 blind release set remains sealed. The research runner accepts only the retired set and the new challenge. It issues no release receipts.

Use `followup.py replay --role revised --lanes rules,hybrid` on the retired corpus with the same `--input`, `--output`, `--destination` and `--derived-data` options as the development runner. In CI, `--lanes rules` runs offline. The recovery check requires the expected action, eligible workout IDs, accepted first match, and annotated filters on all 90 regression queries. It also catches leftover keywords that can hide behind a correct empty result. The test host emits applied filters and ordered workout IDs into the observation JSON. The fresh replay requires the successful retired-run manifest as `--candidate-receipt` and `--existing-build`, which ties both phases to exactly the same binary. Supply `--lanes rules,hybrid,forcedModel` to also request actual on-device interpretation of simple queries. The forced diagnostic uses the same prompt and validator as the opt-in hybrid. Unsupported conditions and model failures can still use the fallback.

Run `followup.py replay --role prior --existing-build --lanes rules` against the archived prior binary and each corpus to obtain paired priors. To reconstruct the exact measured follow-up source state, first apply `git apply scripts/search-evaluation/prompts/replay-measured-ui.patch` in a separate checkout. This reverses the empty-state copy and presentation update that followed measurement. The reconstructed follow-up source fingerprint is `ee73d760d6d1577a7ede7f588119fee4598db61668670e5cacfb22443590530c`. To rebuild the prior binary from that reconstructed checkout, apply `git apply scripts/search-evaluation/prompts/replay-prior-rules.patch`, and omit `--existing-build`. The runner verifies the complete Swift source fingerprint against the original receipt before building. The aggregate report identifies rebuilt versus originally measured binaries. To score, use `followup.py report --input <corpus> --prior <prior-output> --revised <revised-output> --output <aggregate-json>`. Optional `--development-diagnostics <file>` exports failure examples only from the retired cohort. Keep the challenge query-level observations in custodian storage.

## Fast engine replay

[engine-harness](engine-harness/README.md) replays the development, validation and annual sets straight against the engine source in seconds, with no simulator. Use it while changing the parser or scoring, then confirm with the simulator runs below. Ranked search returns best matches as `ids` and near misses as `closeIDs`; `score.py` reports `topThree`, the share of positive searches whose expected workout is in the first three rows on screen.

## Development

Choose an available simulator UDID and a new output directory for each run. Example commands assume the current directory is the repository root.

```sh
python3 scripts/search-evaluation/corpus.py verify
python3 -B scripts/search-evaluation/test_scoring.py
python3 scripts/search-evaluation/corpus.py export --split development --output /tmp/search-dev/corpus.json
python3 -B scripts/search-evaluation/run.py --input /tmp/search-dev/corpus.json \
  --derived-data /tmp/search-build --destination "$SIMULATOR_UDID" \
  --output /tmp/search-probe --lanes hybrid --probe
```

Inspect the probe's `observations.json`. Check that `modelAttempted` is true and that a production response was returned or rejected by the validator. Apple can report the model is available while the inference assets fail to load. A generation failure gives no evidence about the quality of the prompt.

```sh
python3 -B scripts/search-evaluation/run.py --input /tmp/search-dev/corpus.json \
  --derived-data /tmp/search-build --destination "$SIMULATOR_UDID" \
  --output /tmp/search-development --existing-build --repeats
python3 -B scripts/search-evaluation/score.py --input /tmp/search-dev/corpus.json --run /tmp/search-development
```

The default lanes run legacy search, deterministic structured search, and the hybrid production interpreter. The app-hosted XCTest shares the same fixture records across lanes and checks record fields against the source. It replays 180 unique development queries and, with `--repeats`, runs two additional hybrid passes for a fixed family-stratified subset of 30. Each inference starts a fresh language model session with greedy sampling. Use `--lanes legacy,rules` for a model-independent comparison. Each run includes all tests in the search engine, session and legacy query regression suites, and fails on missing or unsuccessful suites.

The runner fingerprints the product and test sources, built executables, prompt source and corpus. Rebuild after edits by omitting `--existing-build`. Inputs and gold must match the checked-in v1 fingerprints. The test bundle receives only the synthetic inputs, the clock and lane settings. The host Python scorer receives gold separately.

## Reading a run

* **Task success** counts the correct first result for a ranked query, accepts recorded first-place ties, checks the exact set for filtered queries, and requires the expected empty or clarification action. Clarification must offer the distinct expected places. Counts, simple/conversational splits, macro average by intent category and paired wins/losses/ties accompany every comparison.
* **Diagnostics** include result precision/recall, reciprocal rank, slot micro-F1 for structured interpreters, violations of explicit predicates, fallback status and variation across repeats. A protected temporal/numeric/exclusion case also fails the constraint gate if an explicit filter is absent or its protected value contradicts the expected one. A baseline engine with no structured slots receives retrieval scores only.
* **Timing** measures elapsed time to the immediate deterministic result and to the final submitted result. First-call and subsequent-call p50/p95 are separate, with sample counts. One first measurement is descriptive. App-process timings exclude keyboard, drawing, map loading and network geocoding; the operating system can retain model assets between test launches.
* **Artifacts** include an XCResult, observation JSON, manifest and summary. Development also produces per-query JSONL with expected slots, emitted slots and result differences. GitHub's existing Build and test job verifies the scorer, checks the public corpus, runs the real deterministic lanes, and uploads public artifacts. It does not require Apple Intelligence to be enabled on the CI host.

## Refinement and release

A corpus custodian maintains scenarios and labels. A candidate author sees development diagnostics only. An independent evaluator owns validation and blind artifacts, a private release ledger and the separately stored holdout recipe pack. Keep the ledger and pack between runs in access-controlled team storage. Ordinary checkouts include their verifiable fingerprints. Do not regenerate a different blind pack and call it v1.

Group development losses by the first failure: extraction, validation, unit/date conversion, execution or infrastructure. Fix the responsible component. Change one prompt instruction or schema description for a recurring extraction failure and evaluate the complete development corpus against the same fixture version. Record the hypothesis, candidate fingerprint and resulting paired changes. An infrastructure failure requires a model-capable runtime before drawing prompt conclusions.

The v1 validation questions were subsequently opened to diagnose 48 known false-empty searches. Their answers now serve as regression checks in CI. A new promotion evaluation requires an independently frozen validation split. The v1 blind set remains sealed.

For a promotion-eligible validation split, export validation in the private evaluator workspace and use the same run/score commands with `--existing-build`. Pass `--development-summary /tmp/search-development/summary.json --custody-dir <private-ledger>` to the runner and the same `--development-summary` to the scorer. Development qualification includes complete 30×3 repeat coverage. Each hybrid validation attempt reserves one of three ledger slots. A separate one-time audit accepts `--lanes legacy,rules` with a matching frozen development binary, even when the model fails its development gate. Its aggregate results describe deterministic generalization and cannot qualify a model candidate. Run validation and blind serially under the same independent custodian.

A qualifying validation score issues `freeze.json`. The custodian supplies the verified private pack to `corpus.py export --split holdout --private-pack <pack> --output <private-dir>/corpus.json`, then runs all three lanes once using the same tested binaries with `--freeze <freeze.json> --custody-dir <private-ledger> --existing-build`. A changed binary or source hash invalidates the receipt. The release ledger is consumed before blind execution. Keep raw observations and XCResults private; share aggregate metrics. A further iteration following blind failure needs a fresh locked evaluation set.

Promotion requires passing deterministic regressions, zero protected constraint violations, a conversational task-success gain of at least five percentage points over rules, and a positive lower bound on a paired 95% interval. The scorer bootstraps 5,000 samples of independent scenario families with both lanes kept paired. A genuine successful model interpretation must be observed; fallback agreement alone cannot qualify. Shipping enablement is a separate reviewed change after a passing blind run.

## Six-month runner study

The [runner study report](runners/report.md) grades 500 search attempts against answers written before execution. Ten independent GPT-6.1 Terra runners at medium reasoning effort each supplied six months of fictional runs and 50 questions. The [histories](runners/histories) record their original words, expected workout IDs and ranking preferences. This public corpus is suitable for regression analysis. A future independent evaluation needs new runners and questions.

Build the WindRun scheme for testing on an iPhone simulator. Run the following command with its generated test configuration and simulator ID. Use a new output directory. The harness makes the fixtures into real workout models, including sampled route segments, and executes the default search path. Only the host grader receives the answer keys.

~~~sh
python3 -B scripts/search-evaluation/runner_study.py \
  --configuration "$derived/Build/Products/$configuration" \
  --destination "$simulator" --output "$output"
~~~

The runner histories label route shape. The fixture converts that label into GPS fixes on up to one kilometer of each workout's route. Climbs and descents use 9% grades, out-and-backs return to their starting point and elevation, rolling terrain stays below the steep grade threshold, and noisy-flat terrain oscillates around a constant height. Unknown profiles supply no route. The search engine sees only the recorded samples. The dated records use a neutral 09:00 UTC start because the authors supplied calendar dates.

Pass `--terrain-controls` with a separate output directory to replay “hills”, “uphill” and “downhill” against each history. The [500 runner attempts](runners/answers.jsonl) and [30 literal controls](runners/terrain-controls.jsonl) preserve the expected IDs and the app's actual ordered IDs for independent scoring.

## Annual weekly-checkpoint study

The [annual study report](year-study/report.md) covers ten synthetic workout histories and 1,200 queries per trial. The [simulator replay guide](year-study/README.md) explains how to run and grade the frozen fixtures.

## Opt-in beta feedback

A tester can enable **Personalization → Label empty searches** and label an empty result with **No match is right** or **I expected a workout**. The latter opens the workout picker. Labels stay in the app's protected local storage and can be deleted in Personalization.

With an empty search box, open **Compare saved search feedback**. Both lanes use the saved query date and calendar and the same available workout records. A positive label asks whether the selected workout appears anywhere in the results. A negative label requires an empty result without a place clarification. The comparison reports these denominators separately, along with missing selections, model attempts and accepted responses. Testers can share the totals. Edits to historical workout details can change a later replay.

For a held-out comparison, collect labels from testers whose examples were not used to change the parser or prompt and run both lanes on a fixed app build. Keep these labels separate from development feedback. This cohort measures previously empty searches that testers chose to label. Estimating accuracy across all searches would require sampling successful searches as well.
