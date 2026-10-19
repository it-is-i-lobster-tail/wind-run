# Distance running literature collection

This folder is the evidence base for Wind Run's coach and interval features. It collects peer-reviewed research, consensus statements, clinical guidelines and training-plan templates from trusted organizations on distance running from 5K to the marathon.

This is the **collection** step. Each source was found, given an initial read to confirm it fits, and catalogued with a short summary. The in-depth analysis and synthesis come later.

## Questions the collection covers

| # | Topic | Question |
|---|---|---|
| 01 | Coaching and training principles | How should a distance runner be coached? Overload, specificity, individualization, periodization and the fitness-fatigue model. |
| 02 | Increasing distance | How fast can weekly distance safely increase (the 10% rule, load spikes, long-run progression)? |
| 03 | Training frequency | How many days per week should an athlete run, and how should rest days be placed? |
| 04 | Missed training, detraining and return | How should training change when days or weeks are missed because of illness, life or travel? |
| 05 | Training around minor pain | How should training be modified for minor pain (shin splints, sore feet, tendon pain), and which signs mean stop and see a professional? |
| 06 | Speed development | How does an athlete train to get faster (intervals, threshold, VO2max work, sprints, hills)? |
| 07 | Mixing speed and distance work | How should hard sessions be mixed with easy distance running (polarized, pyramidal, threshold, 80/20)? |
| 08 | Preparing for an event | With a fixed amount of time before an event, how should distance and speed work be combined, and how should the taper and race pacing work? |
| 09 | Using past performance | How can past performances predict race times, set training paces and adjust a program? |
| 10 | Injury risk and training errors | Which common program errors and risk factors lead to injury or overworking the athlete? |
| 11 | Overtraining, recovery and sleep | How do overreaching, overtraining and low energy availability show up, and what do recovery and sleep contribute? |
| 12 | Strength and cross-training | What do strength training, plyometrics and cross-training add for distance runners? |
| 13 | Physiology and performance determinants | What determines distance running performance and how does it adapt to training? |
| 14 | Nutrition and fueling | How should runners fuel and hydrate for training and racing? |
| 15 | Beginners and adherence | What works for new runners (couch-to-5K style programs), and why do people drop out? |
| 16 | Special populations | How should training differ for masters runners, female athletes, pregnancy and postpartum, youth and higher-BMI novices? |
| 17 | Monitoring load and wearables | How can training load and readiness be measured (heart rate, HRV, RPE, GPS, wearables), and how accurate are the devices? |
| 18 | Running form, footwear and biomechanics | What does the evidence say about cadence, footstrike, shoes and running mechanics? |
| 19 | Environment: heat, altitude and terrain | How should training and pacing adjust for heat, cold, altitude and hills? |
| 20 | Organization guides and plan templates | What training plans, coaching manuals and guides do trusted running and health organizations publish? |

## Layout

```
research/
  README.md            this file: scope, method, where the full texts live
  INDEX.md             every source in one table per topic (generated)
  sources.json         the catalog: one record per source (source of truth)
  topics.json          topic numbers, names and questions
  search-logs/         queries and databases used, and notable rejections
  library/NN-topic/    README.md with every source's citation, links, summary and abstract
  library-local/       git-ignored; downloaded full texts, created by the fetch script
  scripts/
    fetch_library.py   looks up abstracts and licences, downloads open full texts, rebuilds the index
    build_index.py     regenerates INDEX.md and the topic READMEs from sources.json
```

Each source has one primary topic (its folder) and may be tagged with others; topic READMEs list those cross-references at the end.

## Method

1. **Scope.** The questions above, for adult recreational to sub-elite runners training for 5K to marathon. Elite studies are included when they describe training practice that informs recreational coaching.
2. **Search.** Nine parallel searches, one per group of topics, using web search (which indexes PubMed, PubMed Central, publisher sites and organization sites), the Europe PMC search API, and publisher and organization pages. Queries for each group are in `search-logs/`. A follow-up pass with direct access to the Europe PMC and OpenAlex APIs then checked the leads those searches could not verify and filled the thinnest topics (`search-logs/mac-follow-up-pass.md`).
3. **Inclusion.** Priority to systematic reviews and meta-analyses, randomized trials, large prospective cohorts and big-data analyses, consensus statements, position stands and clinical practice guidelines, then landmark narrative reviews and classic papers. For plan templates, only established organizations (health services, governing bodies, coaching-education bodies, major race organizers), plus a few widely trusted coaches' methods, labelled as such. Evidence that contradicts common advice (for example, trials that question the 10% rule) is included on purpose.
4. **Initial read.** Every source was opened (abstract, publisher page, Europe PMC record or the document itself) to confirm it exists and fits a question. The `summary` and `relevance` fields are notes in our own words from that initial read. They are not a critical appraisal and may contain errors; check the source before relying on a number.
5. **Identifiers.** DOIs, PMIDs and PMCIDs were recorded only when seen on a page or API record. `fetch_library.py` fills in missing ones from Europe PMC, OpenAlex and Crossref.

## Where the full texts live

The repository holds the catalog only: citations, links, summaries and abstracts. Full texts are never committed, which keeps the app repository small and avoids republishing anything (the repository is public).

- **Open copies** (open-access papers and organization guides): `fetch_library.py` downloads them into the git-ignored `library-local/NN-topic/` folder on the machine that runs it, as PDF, Europe PMC or PMC full-text XML, or an HTML snapshot of a guide page. Each record's `local_files` lists its copies.
- **Licence per copy:** `open_licence_copies` names the copies that carry an open licence themselves (Creative Commons, public domain, UK Open Government Licence). When only a repository or author-manuscript copy is openly licensed, the publisher's PDF is not counted as open. Snapshots are copies of each page as it was on its `fetched_at` date; check the live page (`url`) for current advice.
- **Paywalled** (including books): citation, link, summary and abstract only. Get these through a library or the publisher.

To get the full texts on another machine, copy an existing `library-local/` folder into `research/`, or run `python3 research/scripts/fetch_library.py`.

Abstracts are reproduced from the Europe PMC, OpenAlex or Crossref APIs for research use, with the source of each abstract noted.

## Refreshing or extending the collection

```sh
# add or edit records in research/sources.json, then:
python3 research/scripts/fetch_library.py            # enrich metadata and download open copies
python3 research/scripts/fetch_library.py --only some-source-id
python3 research/scripts/build_index.py              # regenerate Markdown only
```

`fetch_library.py` needs Python 3.9+ and `curl`, and uses only the standard library. It is safe to re-run: files already downloaded are skipped, and it never tries to get around paywalls or bot checks.

### Record fields

`id`, `title`, `authors`, `year`, `venue`, `doi`, `pmid`, `pmcid`, `url`, `pdf_url`, `source_type`, `topics` (first is primary), `access`, `license`, `summary`, `relevance`, `found_via`; added by the fetch script: `abstract`, `abstract_source`, `oa_status`, `local_files` (downloaded copies, paths relative to `research/`), `open_licence_copies`, `fetch_status`, `fetched_at`.
