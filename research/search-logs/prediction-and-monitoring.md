# Search log - researcher H (performance-prediction-and-adjustment; monitoring-load-and-wearables)

Date: 2026-10-18. Final catalog: 70 sources in H.json.

Engines/databases used: WebSearch (standard mode), OpenAlex API (DOI lookups, multi-DOI batch lookups, title searches), Semantic Scholar Graph API (DOI lookups for identifiers, OA links, abstracts/TLDRs), publisher and repository landing pages (BMC, MDPI, Frontiers, USENIX, university repositories at Hertfordshire, Kent, Bologna, AUT, Jyvaskyla), sport-science bibliographic databases (LIDA/IAT, SPONET, BISp SURF), RePEc/IDEAS, Redalyc.

## Access problems encountered (affects coverage)
- Europe PMC REST API returned HTTP 429 (proxy rate limit) on all 5 attempts, so it could not be used; OpenAlex and Semantic Scholar were used instead for metadata/abstracts.
- NCBI E-utilities blocked by robots.txt; api.crossref.org, link.springer.com and nature.com article pages failed to fetch; scinapse.io serves a captcha.
- The shared WebSearch budget (200 calls per turn across all 9 researchers) was exhausted after my ~21st search, so most discovery after that point used OpenAlex title search and DOI lookups.
- The shared WebFetch budget (400/hour across all agents) was repeatedly exhausted; calls were spaced out and batched (3 DOIs per OpenAlex call).

## WebSearch queries (standard mode)
1. Vickers Vertosick 2016 "An empirical study of race times in recreational endurance runners" BMC
2. Emig Peltonen 2020 "Human running performance from real-world big data" Nature Communications
3. Riegel 1981 "Athletic records and human endurance" American Scientist 69
4. jstor Riegel "Athletic Records and Human Endurance" ... "American Scientist" 1981
5. Blythe Kiraly 2016 PLoS One "Prediction and quantification of individual athletic performance of runners"
6. Keogh 2019 "Prediction equations for marathon performance: a systematic review" IJSPP
7. Alvero-Cruz "Predictive Performance Models in Long-Distance Runners: A Narrative Review" IJERPH 2020
8. Tanda 2011 "Prediction of marathon performance time on the basis of training indices" J Hum Sport Exerc
9. Smyth Muniz-Pumares 2020 "Calculation of Critical Speed from Raw Training Data in Recreational Marathon Runners"
10. Jones Vanhatalo 2017 "The 'Critical Power' Concept: Applications to Sports Performance..." Sports Medicine
11. Poole Burnley Vanhatalo Rossiter Jones 2016 "Critical Power: An Important Fatigue Threshold in Exercise Physiology"
12. Tanaka Monahan Seals 2001 "Age-predicted maximal heart rate revisited" J Am Coll Cardiol
13. Foster Florhaug Franklin 2001 "A new approach to monitoring exercise training" JSCR session RPE
14. Borg 1982 "Psychophysical bases of perceived exertion" MSSE
15. Impellizzeri Marcora Coutts 2019 "Internal and External Training Load: 15 Years On" IJSPP
16. Plews Laursen Stanley Kilding Buchheit 2013 "Training adaptation and heart rate variability in elite endurance athletes..."
17. "Training adaptation and heart rate variability in elite endurance athletes" Sports Med 2013 doi
18. Kiviniemi Hautala Kinnunen Tulppo 2007 "Endurance training guided individually by daily heart rate variability measurements"
19. Duking 2021 "Monitoring and adapting endurance training on the basis of heart rate variability monitored by wearable technologies"
20. Manresa-Rocamora 2021 "Heart Rate Variability-Guided Training for Enhancing Cardiac-Vagal Modulation..."
21. Granero-Gallegos 2020 "HRV-Based Training for Improving VO2max in Endurance Athletes" (refused: shared budget exhausted)

## Semantic Scholar Graph API lookups (/paper/DOI:...)
Emig 2020; Vickers 2016; Blythe 2016; Keogh 2019; Plews 2013; Kiviniemi 2007; Duking 2021; Javaloyes 2019; Bellenger 2016 (abstract elided, TLDR only); Halson 2014; Doherty 2020 (abstract); Muniz-Pumares 2024 (green OA link). One title-search call and one PMCID lookup failed.

## OpenAlex lookups
Single-DOI/work lookups: Borg 1982 (W2004008756); Smyth & Muniz-Pumares 2020; Granero-Gallegos 2020; Vesterinen 2016; Manresa-Rocamora 2021; Nuuttila 2022; Bellenger 2016; Bourdon 2017.
Multi-DOI batches (filter=doi:A|B|C with abstract_inverted_index):
- Gilgen-Ammann 2020; Bent 2020; Paquette 2020
- Molina-Garcia 2022; Muhlen 2021; Mann 2013 (no abstract in record)
- Saw 2016; Haddad 2017; Jamnick 2020 (no abstract in record)
- Doherty 2020 (no abstract; abstract later from Semantic Scholar); Mulligan 2018; Mann 2014 (no abstract in record)
- Mayorga-Vega 2016; Galbraith 2014; Plews 2017
- Impellizzeri 2020 (ACWR); Imbach 2022; Altini & Plews 2021
- Reed & Pipe 2014; Hecksteden 2015; (DOI intended for Gellish 2007 resolved to Helgerud 2007 - catalogued under speed-development)
- Smyth 2021; Pobiruchin 2017; Mujika 2017
- Manzi 2009 (two other DOIs in the batch, guessed for Sylta 2014 and Bosquet 2008, did not resolve)
- Jones & Doust 1997 attempt (DOI resolved to Hawley et al. 1997 instead - not catalogued); Chen 2002; Morton 1990
- Gillinov 2017; Imbach 2020 (Stryd); Shcherbina 2017
- Stone 2021; Miller 2022; Iannetta 2020
- Two longer batch URLs were silently ignored by the server (filter dropped) or refused as too long.
Title searches (filter=title.search:...):
- "privacy protections fitness tracking social networks" -> Hassan et al. 2018 (then read full PDF on usenix.org)
- "training intensity distribution marathon runners performance levels" -> Muniz-Pumares 2024 (abstract read in AUT repository PDF)
- "age-predicted maximal heart rate HUNT fitness study" -> Nes 2011 MSSE abstract (the 2013 full paper was not found)
- "heart rate convenient tool monitor over-reaching" -> Bosquet 2008
- "Conconi test not valid lactate turnpoint runners" -> Jones & Doust 1997
- "Daniels running formula" -> Daniels' Running Formula (Human Kinetics 2022 book record)
- "heart-rate data training quantification comparison 3 methods" -> Sylta 2014
- "session rating perceived exertion training volume runners" -> Napier 2020
- "are we ready to measure running power" -> Cerezuela-Espejo 2021
- "lactate threshold concepts how valid are they" -> 0 results (Faude 2009 not verified)
- "means of assessing maximal oxygen intake" -> Cooper 1968 (two duplicate records)

## Publisher / repository pages read
BMC (Vickers); RePEc (Emig, Alvero-Cruz); MDPI (Alvero-Cruz, Manresa-Rocamora); Redalyc PDF (Tanda); U. Hertfordshire repository (Smyth 2020); GSSI page (Jones & Vanhatalo); U. Kent repository (Poole); CU Boulder VIVO + full-text copy (Tanaka); SPONET + author PDF (Foster); U. Bologna IRIS (Impellizzeri 2019); AUT repository (Plews thesis; Muniz-Pumares 2024 PDF); LIDA/IAT (Keogh, Kiviniemi, Vesterinen 2016, Duking); BISp SURF (Vesterinen 2013); Frontiers (Buchheit 2014); USENIX PDF (Hassan 2018); course-hosted PDF copy (Riegel 1981).

## Notes on catalog conventions
- access "free-to-read" is used when a free full text was seen (gold/bronze/green OA, PMC, repository copy) but no licence statement was verified; "open-license" only when a CC licence was seen in a page or API record.
- Several OpenAlex records lacked abstracts (Mann 2013, Mann 2014, Jamnick 2020, Bellenger 2016); those summaries describe the review's stated scope and should be checked against full text during in-depth analysis.

## Notable candidates rejected or not catalogued (and why)
- Cameron race-prediction model: not a peer-reviewed publication; no citable primary source found.
- Daniels & Gilbert 1979 "Oxygen Power" tables: could not verify a record; represented by Daniels' Running Formula (2022) instead.
- Plews 2014 PhD thesis (AUT): read, but duplicates Plews 2013 and companion papers; mentioned inside the Plews 2013 entry.
- Hawley et al. 1997 "Training techniques to improve fatigue resistance and enhance endurance performance" (J Sports Sci): surfaced by a DOI lookup; mainly cyclists and an older narrative review, low priority.
- "Relationships between workload, HRV and performance in a recreational endurance runner" (JFMK 2021): single-runner case study.
- Nes et al. 2013 HUNT full paper: not found in OpenAlex title search; the 2011 MSSE abstract with the same data was catalogued instead.

## Unverified leads (not catalogued: not initially read because of budget limits). Titles only - verify before use.
- Vandewalle H 2018, BioMed Research International - comparison of power-law, hyperbolic, logarithmic and exponential models of running records.
- Faude O, Kindermann W, Meyer T 2009, Sports Medicine - "Lactate threshold concepts: how valid are they?".
- Montero D, Lundby C 2017, J Physiol - "Refuting the myth of non-response to exercise training".
- Gellish RL et al. 2007, MSSE - longitudinal modelling of age and HRmax; Robergs RA, Landwehr R 2002, JEPonline - history of the 220-age formula.
- Swain DP, Leutholtz BC 1997, MSSE - heart rate reserve vs %VO2 reserve.
- Scherr J et al. 2013, Eur J Appl Physiol - Borg RPE vs heart rate and lactate in a large sample.
- Quinn TJ, Coons BA 2011, J Sports Sci - talk test vs ventilatory and lactate thresholds.
- Pettitt RW et al. 2012, Int J Sports Med - 3-min all-out running test for critical speed.
- Borresen J, Lambert MI 2009, Sports Medicine - quantification of training load and response.
- Clarke DC, Skiba PF 2013, Adv Physiol Educ - teaching mathematical modelling of training and performance.
- Navalta JW et al. 2020, PLoS ONE - wearable HR validity during trail running.
- Jaen-Carrillo D et al. 2020, Sensors - scoping review of running power sensors.
- Adams D et al. 2016, JOSPT - validity of a fitness watch for running dynamics.
- Nielsen RO et al. - Garmin-RUNSAFE Running Health Study (wearable-based injury cohort) and its analyses of single-session distance spikes (injury topic).
