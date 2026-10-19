# Search log: researcher C

Scope: `minor-pain-and-injury-modification` (primary) and `running-form-footwear-and-biomechanics` (primary). Strongly relevant items for other topics were logged with their slugs.

Output: `catalog/C.json`, which holds 107 sources. It is built from `C_parts/part*.json` by `scripts/merge.py`, which checks:
- key order
- allowed topic, type and access values
- integer years
- the PMC prefix
- duplicate ids and DOIs

## Engines and databases used

- **WebSearch (open web).** Used only at the start. The shared budget (200 calls per turn across all agents) ran out after 15 queries from this researcher.
- **Europe PMC REST API** (`/search`, `resultType=core`). It often returned HTTP 429 (rate-limited). It was used whenever it answered, for example for the Silbernagel 2007, Moen 2009 and Neal 2016 abstracts.
- **Crossref REST API** (`query.bibliographic`). Used for metadata and to confirm DOIs.
- **Semantic Scholar Graph API** (`paper/DOI:...`). Used for abstracts. The search endpoint was throttled.
- **OpenAlex API.** This was the main tool:
  - `filter=doi:A|B|C`, with at most 3 DOIs per call; more were ignored.
  - `filter=title.search:...&sort=cited_by_count:desc`.
  - `works/doi:...` and `works/pmid:...`.
  - `select=primary_location,best_oa_location` for licence checks.
  - Abstracts were rebuilt from `abstract_inverted_index`.
- **Publisher, repository and organisation pages:**
  - bjsm.bmj.com, link.springer.com, BMC, journals.plos.org and orthopt.org PDFs.
  - DOAJ and PEDro records.
  - nhs.uk condition pages.
- **Blocked or unusable:**
  - NCBI E-utilities (robots.txt).
  - PubMed/PMC pages (captcha).
  - jospt.org (blocked).

## Budget and rate-limit notes

- **WebSearch:** the shared budget of 200 calls per turn ran out early, and was not worked around. From then on, discovery used:
  - my own knowledge of the literature;
  - OpenAlex title searches sorted by citation count;
  - Europe PMC searches when it answered.

  Every catalogued record was then checked one at a time through bibliographic APIs or publisher pages.
- **WebFetch:** the shared budget of 400 calls per hour ran out more than once (HTTP 403). Calls were then spaced out with 30-150 s waits rather than retried in a loop.
- **HTTP 429:** many calls to Europe PMC, Crossref, Semantic Scholar, OpenAlex, doi.org and Springer were rate-limited. A URL refused with 429 was never fetched again; the same records were requested later with a different grouping.
- **Wrong or junk results:**
  - Crossref's multi-DOI `filter` and an OpenAlex 5-DOI filter returned unrelated works.
  - Semantic Scholar mapped DOI 10.1136/bjsports-2017-098296 to the wrong paper.
  - All of these were caught and discarded.

## Queries and lookups (one per line, in order)

### WebSearch (open web), before the budget ran out

- Midportion Achilles Tendinopathy clinical practice guideline revision 2024 JOSPT Martin Chimenti
- "Achilles Pain, Stiffness, and Muscle Power Deficits: Midportion Achilles Tendinopathy Revision 2018" Martin
- "Heel Pain - Plantar Fasciitis: Revision 2023" JOSPT Koc clinical practice guideline
- "Heel pain--plantar fasciitis: revision 2014" Martin Davenport Reischl McPoil
- heel pain plantar fasciitis revision 2014 CPG recommendations ... orthopt pdf
- midportion Achilles tendinopathy revision 2018 CPG summary of recommendations ...
- Patellofemoral pain consensus statement 4th International ... Manchester Part 2 (open web and pubmed-restricted)
- Willy 2019 "Patellofemoral Pain" clinical practice guidelines JOSPT 49(9)
- 2018 Consensus statement on exercise therapy and physical interventions ... patellofemoral pain Gold Coast Collins
- Esculier 2018 combining gait retraining or an exercise programme with education ... runners patellofemoral pain
- Winters treatment of medial tibial stress syndrome systematic review Sports Medicine 2013
- medial tibial stress syndrome can be diagnosed reliably using history and physical examination Winters 2018 BJSM
- Moen 2012 treatment of medial tibial stress syndrome in athletes randomized clinical trial graded running program ...
- Medial Tibial Stress Syndrome in Novice and Recreational Runners: A Systematic Review Menendez 2020 IJERPH
- Hamstra-Wright 2015 risk factors for medial tibial stress syndrome ... meta-analysis BJSM
- Warden Davis Fredericson 2014 management and prevention of bone stress injuries ... -> NOT RUN. The shared WebSearch budget (200 calls per turn across all agents) was exhausted. From here on, discovery used my own knowledge of the literature, checked record by record through bibliographic database lookups and publisher or repository pages via WebFetch.

### Database APIs, publisher and organisation pages

- Europe PMC REST: AUTH:"Silbernagel" AND TITLE:"pain-monitoring" (resultType=core) -> Silbernagel 2007
- Europe PMC REST: TITLE:"Midportion Achilles Tendinopathy" AND TITLE:"revision" -> HTTP 429 rate limited (Europe PMC rate-limited repeatedly from this point; switched to Crossref + Semantic Scholar APIs + publisher pages)
- Crossref API: query.bibliographic=Patellofemoral pain consensus statement Manchester 2016
- Crossref API: query.bibliographic=Esculier combining gait retraining exercise programme education runners patellofemoral pain
- Semantic Scholar API: DOI lookups for Crossley 2016 part 1/2, Collins 2018, Esculier 2018 (note: S2 mis-mapped DOI 10.1136/bjsports-2017-098296 to a Callaghan editorial; correct Esculier DOI confirmed via Crossref)
- Springer link page: 10.1007/s40279-013-0087-0 (abstract read)
- PEDro record 37780 (Winters 2013 metadata, PMID)
- Crossref API: query.bibliographic=Moen Medial tibial stress syndrome a critical review Sports Medicine 2009
- Europe PMC REST: EXT_ID:19530750 (Moen 2009 abstract)
- DOAJ record cf281595496a49feae31de3f320b20af (Moen 2012 abstract)
- BJSM pages: 52/19/1267 (Winters 2018), 49/6/362 (Hamstra-Wright 2015)
- Semantic Scholar Graph API: DOI:10.1249/MSS.0b013e3181ebedf4 (Heiderscheit 2011)
- Crossref API: query.bibliographic=Lenhart Increasing running step rate reduces patellofemoral joint forces
- Semantic Scholar Graph API: DOI:10.1249/mss.0b013e3182a78c3a (Lenhart 2014)
- Crossref API: query.bibliographic=Anderson effect of changing running step rate ... -> HTTP 403: shared WebFetch budget (400/hour across all agents) exhausted; paced remaining fetches
- Europe PMC REST: (AUTH:"Ryan MB" OR AUTH:"Nielsen RO") AND (TITLE:footwear OR TITLE:pronation) -> 429
- Semantic Scholar Graph API search: Malisoux running shoes injury risk -> error (throttled)
- Crossref API filter=doi:(4 DOIs) -> filter ignored by API, returned unrelated works (wasted call)
- Semantic Scholar Graph API: DOI:10.2519/jospt.2014.5334 (Warden 2014) -> error (throttled)
- NCBI E-utilities esearch -> blocked by robots.txt
- OpenAlex API: filter=doi:10.1136/bjsports-2015-095054|10.1111/sms.12154|10.1038/nature08723 (metadata for Nigg 2015, Malisoux 2015, Lieberman 2010)
- OpenAlex API: 5-DOI filter with abstract_inverted_index -> filter ignored, unrelated works returned (wasted call)
- OpenAlex API (3-DOI filter + abstract_inverted_index): Nigg 2015 / Malisoux 2015 / Lieberman 2010
- OpenAlex API: Malisoux 2020 cushioning / Malisoux 2016 drop / Malisoux 2016 motion control
- OpenAlex API: Nielsen 2014 pronation / Relph 2022 Cochrane / Bonanno 2017
- OpenAlex API: Daoud 2012 / Anderson 2020 / Hoogkamer 2018
- OpenAlex API: Bramah 2019 / Chan 2018 / Doyle 2022
- OpenAlex API: Cook & Purdam 2009 / Silbernagel & Crossley 2015 / Warden 2014
- OpenAlex API: Thomee 1997 / Yamato 2015 / Mueller-Wohlfahrt 2013
- OpenAlex API: Nielsen 2014 recovery / Mulvad 2018 / Linton 2018 -> 429 (retried later with different grouping)
- OpenAlex API: Nielsen 2014 recovery / Linton 2018 (no abstract deposited) / Smith 2017
- OpenAlex API: Mulvad 2018 / Malliaras 2013 / Beyer 2015 -> 429
- OpenAlex API: Mulvad 2018 / Beyer 2015 / Morrissey 2021
- Semantic Scholar Graph API: DOI:10.2147/OAJSM.S39512 (Kahanov 2015)
- OpenAlex API: Malliaras 2013 (no abstract deposited) / Rathleff 2015 / Nattiv 2013
- Semantic Scholar Graph API: DOI:10.2165/00007256-200333020-00005 (Cheung 2003; abstract withheld by publisher)
- OpenAlex API: Schubert 2014 / Anderson 2022 / Fuller 2017
- OpenAlex API: Warne 2017 / Ryan 2011 / Davis 2016 -> 429
- OpenAlex API: filter=title.search:iliotibial band syndrome runners, sort=cited_by_count:desc (Fredericson 2000, Orchard 1996 kept; Ferber 2010 abstract read here and added later; others noted)
- OpenAlex API: Van Hooren 2020 / Warne 2017 / Ryan 2011
- OpenAlex API: Davis 2016 / Ceyssens 2019 (no abstract deposited) / Moore 2016
- OpenAlex API: Knopp 2023 / de Vos 2021 / Silbernagel 2011
- OpenAlex API: Menendez 2020 / Kulmala 2018 / Willwacher 2022
- OpenAlex API: filter=title.search:bone stress injuries runners, publication_year 2018-2026, sorted by cited_by_count (Tenforde 2023, Kliethermes 2021, Warden 2021 x2, Kraus 2019 kept; retracted Tenforde 2021 middle-school survey rejected)
- OpenAlex API: filter=title.search:return to running injury, 2012-2026, sorted by cited_by_count (George 2024 kept; hamstring/football return-to-play papers and AlterG concept paper rejected as off-scope)
- OpenAlex API: filter=title.search:running-related injuries online randomised, sorted by cited_by_count (Hespanhol 2018, Fokkema 2019, Cloosterman 2022 SPRINT, Runfitcheck 2023 kept; INSPIRE protocol and 2014 SSEM trial rejected)
- Semantic Scholar Graph API: DOI lookups for SPRINT 2022 (authors/PMCID) and Fokkema 2019 (authors/PMCID)
- OpenAlex API: filter=title.search:return to sport bone stress injuries, sorted by cited_by_count (Hoenig 2023 kept; adolescent navicular case series, ultrasound cohort, 2026 protocol and volleyball case report rejected)
- Semantic Scholar Graph API: DOI:10.1016/j.jsams.2018.05.021 (Linton 2018 abstract)
- OpenAlex API: Mundermann 2002 (no abstract deposited) / Hollander 2017 / van der Vlist 2021
- OpenAlex API: filter=title.search:running retraining OR gait retraining runners (mixed results; no new items kept: single-case/pilot studies, MTSS retraining protocol 2024 and a commentary without abstract rejected)
- OpenAlex API: filter=title.search:running retraining to treat lower limb injuries (Barton 2016)
- OpenAlex API: Dixon 2000 / Clarsen 2013
- OpenAlex API: filter=title.search:conservative management of Achilles tendinopathy (Silbernagel 2020 kept; Rowe 2012, Alfredson 2005, Hunter 2000 lacked abstracts/older - not added)
- OpenAlex API: filter=title.search:foot core training running-related injuries (Taddei 2020 kept; Suda 2021 secondary analysis noted)
- OpenAlex API: filter=title.search:racing shoes running economy slower speeds (Joubert 2023 kept; Dominy 2022 conference abstract rejected)
- OpenAlex API: filter=title.search:pain-guided hopping Achilles tendinopathy (Sancho 2019, no abstract deposited)
- Europe PMC REST: EXT_ID:31518777 OR EXT_ID:26884223 -> 429; Semantic Scholar Graph API: DOI:10.1016/j.ptsp.2019.08.007 (Sancho 2019 abstract)
- Crossref API: query.bibliographic=optimal stride frequencies in running at different speeds van Oeveren (van Oeveren 2017 PLOS ONE CC BY 4.0; van Oeveren 2019 J Sports Sci noted)
- PLOS ONE article page: 10.1371/journal.pone.0184273 (van Oeveren 2017 abstract + CC BY 4.0)
- OpenAlex API: filter=title.search:delayed-onset muscle soreness pathogenesis diagnostics (Hotfiel 2018)
- OpenAlex API: filter=title.search:running injury development attitudes runners coaches (Johansen 2017 kept); OpenAlex works/pmid:28900570 x2 (source name, PMC location)
- OpenAlex API (3-DOI filter): Fuller 2015 (no abstract deposited) / Richards 2009 / Collins 2008 BMJ
- Semantic Scholar Graph API: DOI:10.1007/s40279-014-0283-6 (abstract elided by publisher; TLDR only)
- Springer landing page: link.springer.com/article/10.1007/s40279-014-0283-6 (Fuller 2015 abstract)
- OpenAlex API: filter=title.search:in-field gait retraining mobile monitoring tibial stress fracture (Willy 2016 kept)
- OpenAlex API (3-DOI filter): Ardern 2016 RTS consensus / Hamill & Gruber 2017 / van der Worp 2016 -> 429 (URL not retried; items re-tried individually later where budget allowed)
- OpenAlex API: works/doi:10.1136/bmjsem-2022-001522 x2 (Runfitcheck RCT, van der Does 2023: authors, abstract, ids, locations, CC BY-NC)
- OpenAlex API: works/doi:10.1136/bjsports-2016-096278 (Ardern 2016 RTS consensus kept)
- OpenAlex API: filter=title.search:iliotibial band syndrome systematic review, sorted by cited_by_count -> 429 (not retried)
- OpenAlex API (3-DOI filter): Ferber 2010 / Noehren 2007 (no abstract deposited) / Aderem & Louw 2015
- BMC article page: 10.1186/s12891-015-0808-7 (Aderem 2015 abstract details + CC BY 4.0)
- Semantic Scholar Graph API: DOI:10.1016/j.clinbiomech.2007.07.001 (Noehren 2007 prospective ITBS) -> fetch error; not added (abstract not read)
- OpenAlex API (3-DOI filter): Hamill & Gruber 2017 / Fredericson 1995 MRI grading / Bachmann 2003 Ottawa ankle rules SR
- OpenAlex API: filter=title.search:runners injuries higher vertical ground reaction forces injury-free (van der Worp 2016 kept)
- OpenAlex API: filter=title.search:runners patellofemoral pain altered biomechanics targeted interventions modify (Neal 2016; no abstract deposited)
- Semantic Scholar Graph API: DOI:10.1016/j.gaitpost.2015.11.018 (abstract elided by publisher)
- Europe PMC REST: EXT_ID:26979886 (Neal 2016 abstract read; Europe PMC answered again at this point)
- Europe PMC REST: TITLE:"plantar fasciopathy" AND TITLE:"heavy-slow resistance" (Riel 2019) -> 429 (not retried)
- OpenAlex API: filter=title.search:self-dosed heavy-slow resistance training plantar fasciopathy (Riel 2019 kept)
- NHS website: nhs.uk/conditions/shin-splints (organisation guidance, red flags; kept)
- NHS website: nhs.uk/conditions/sprains-and-strains (escalation tiers / red flags; kept)
- NHS website: nhs.uk/conditions/achilles-tendinopathy -> fetch error (page not read; not added)
- NHS website: nhs.uk/conditions/plantar-fasciitis (escalation criteria; kept)
- OpenAlex API: filter=title.search:real-time gait retraining hip kinematics pain function patellofemoral (Noehren 2011) -> 429 (not retried; not added)
- OpenAlex API: filter=title.search:dermatological injuries marathon (Mailler & Adams 2004 kept; abstract only states scope)
- BJSM PDF bjsports/38/4/498.full.pdf -> fetch error; BJSM landing page content/38/4/498 (abstract only)
- OpenAlex API (3-DOI filter, select=primary_location,best_oa_location): licence check Nielsen 2014 / Mulvad 2018 / Kulmala 2018 (all cc-by)
- OpenAlex API (3-DOI filter, select=primary_location,best_oa_location): licence check Anderson 2022 / Warne 2017 / Menendez 2020 (all cc-by; version not stated, so recorded as 'CC BY')

## Notable rejected candidates and why

### Off-scope or low-level evidence

- **Tenforde et al. 2021** (survey of bone stress injury in middle-school runners): retracted.
- **Hamstring and football return-to-play papers** from the 'return to running' searches: off-scope (team sport, not distance running).
- **AlterG anti-gravity treadmill concept paper:** off-scope (equipment few runners have).
- **From the bone-stress return-to-sport search:** weak design, protocol only, or not about running. This covers:
  - an adolescent navicular stress fracture case series;
  - an ultrasound cohort;
  - a 2026 protocol;
  - a volleyball case report.
- **From the gait-retraining searches:** weak design, protocol only, or no abstract to read. Doyle 2022, Barton 2016, Chan 2018 and Willy 2016 cover this ground. This covers:
  - single-case and pilot studies;
  - a 2024 MTSS gait-retraining protocol;
  - a commentary with no abstract.
- **Dominy et al. 2022** (conference abstract on super-shoes at slower speeds): conference abstract only. The full paper (Joubert 2023) was kept instead.

### Superseded or redundant

- **INSPIRE trial protocol:** protocol only. The results paper (Fokkema 2019) was kept.
- **An older (2014) online-prevention trial** in the 'running-related injuries online randomised' result set: older and less relevant. Hespanhol 2018, Fokkema 2019, Cloosterman 2022 and van der Does 2023 were kept instead.
- **Suda et al. 2021** (secondary analysis of the foot-core trial): secondary analysis. The main RCT (Taddei 2020) was kept.

### No abstract could be read

These were not catalogued because of the 'initially read' rule.

- **Rowe 2012, Alfredson 2005 and Hunter 2000** on Achilles tendinopathy management: older, with no abstract in the record.
- **Noehren, Davis and Hamill 2007** (Clin Biomech 22(9):951-956), the prospective ITBS biomechanics study: no abstract in OpenAlex, and the Semantic Scholar lookup failed. Its key finding (greater hip adduction and knee internal rotation before ITBS) is reported through Aderem & Louw 2015.
- **'Iliotibial band syndrome in runners' 2005** (Sports Med 35(5):451-459; DOI 10.2165/00007256-200535050-00006): no abstract in the record.
- **Noehren et al. 2011** (real-time gait retraining for patellofemoral pain, BJSM): the OpenAlex title search was rate-limited (429) and not retried. Neal 2016, Barton 2016 and Doyle 2022 cover the evidence.
- **NHS 'Achilles tendinopathy' page:** fetch error, so not read and not added. The NHS shin splints, sprains and strains, and plantar fasciitis pages were added.

### Older ITBS papers seen but not added

- **'Iliotibial band friction syndrome in runners' 1980** (AJSM 8(4):232-234; DOI 10.1177/036354658000800403): a case series from the steroid-injection era; old and low-level.
- **'Etiology of iliotibial band friction syndrome in distance runners' 1995** (MSSE 27(7):951-960; DOI 10.1249/00005768-199507000-00002): the record showed no authors, and newer reviews cover it.

### Bibliographic problems

- **Esculier 2018 DOI:** Semantic Scholar mapped DOI 10.1136/bjsports-2017-098296 to a Callaghan editorial. Crossref confirmed the correct DOI as 10.1136/bjsports-2016-096988.
- **van Oeveren 2019** (J Sports Sci; DOI 10.1080/02640414.2019.1614137): seen in Crossref, but the abstract was not read before the budget ran out, so it was not catalogued.

## Entries that need a closer read before use

**Summaries partly based on the record or on known published content, because no abstract was deposited:**
- Anderson 2020
- Malliaras 2013
- Ceyssens 2019
- Cheung 2003
- Mündermann 2002
- Warden 2021 (JOSPT and COR)
- Lieberman 2010
- Mailler & Adams 2004: the abstract states only the scope.

**Licences recorded only where seen** in a page or API record. Where OpenAlex gave `cc-by` without a version, the licence is recorded as "CC BY".
