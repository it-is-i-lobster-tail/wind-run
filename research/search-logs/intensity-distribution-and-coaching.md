# Search log: scope F (intensity-distribution; coaching-and-training-principles)

## Status
- 34 sources catalogued in F.json (all checked against an abstract, landing page or API record; see each entry's `found_via`).
- The work stopped early because BOTH shared budgets ran out:
  1. WebSearch: the per-turn budget (200 calls shared by all 9 agents) ran out after ~33 of my queries (3 more queries were refused).
  2. WebFetch: the proxy then reported the shared fetch budget exhausted (400/hour across all agents) and said not to retry in a loop. No further fetching was attempted.
- Europe PMC REST API was rate-limited (HTTP 429) on all but one call, so most PMIDs come from PubMed URLs in search results or from repository pages, not from Europe PMC.

## Engines / databases used
- WebSearch (standard mode) for discovery; PMIDs/PMCIDs taken only from PubMed/PMC URLs shown in results (title-matched where the result showed a title).
- Europe PMC REST API (via WebFetch): worked once (EXT_ID:20861519 AND SRC:MED). Later calls got HTTP 429 (rate limited); one multi-title OR query was rejected (HTTP 403) because the URL was too long for the proxy.
- NCBI E-utilities: blocked (robots disallowed). Semantic Scholar Graph API: fetch error.
- Crossref REST API (api.crossref.org/works/{doi} and ?query.bibliographic=...): used to verify DOIs, author lists, pages and licence URLs. It sometimes returned fetch errors. Lesson: `filter=doi:a,doi:b` does not work as an OR lookup and returns unrelated records.
- Publisher and repository landing pages: frontiersin.org (HTML + PDF), link.springer.com (HTML + PDF), journals.humankinetics.com, and university repositories: Bath, Universidad Europea (Abacus), UPV/EHU, Nebrija, Stirling, Tübingen, Wolverhampton, Griffith, AUT, and the Norwegian Brage instances (UiA, UiS, NIH). Also lida.sport-iat.de / SPONET (German sport-science literature database records with abstracts), IDEAS/RePEc, and bibgraph.hpcr.jp (a PubMed mirror, used to confirm one PMID).
- Blocked or unusable: MDPI (automated-access check), Thieme (bot protection), HAL (Anubis bot protection), scinapse.io (reCAPTCHA), Leeds Beckett e-prints (robots), Norwegian NVA (requires JavaScript).

## WebSearch queries (one per line)
- Seiler 2010 "What is best practice for training intensity and duration distribution in endurance athletes"
- Seiler Kjerland 2006 "Quantifying training intensity distribution in elite endurance athletes" Scand J Med Sci Sports
- Stöggl Sperlich 2014 "Polarized training has greater impact on key endurance variables" Frontiers in Physiology
- Esteve-Lanao 2005 "How do endurance runners actually train? Relationship with competition performance"
- Esteve-Lanao 2007 "Impact of training intensity distribution on performance in endurance athletes" J Strength Cond Res
- Muñoz Seiler 2014 "Does polarized training improve performance in recreational runners?" IJSPP
- Haugen Sandbakk Seiler Tønnessen 2022 "The Training Characteristics of World-Class Distance Runners" Sports Medicine Open
- Casado González-Mohíno González-Ravé Foster 2022 "Training Periodization, Methods, Intensity Distribution, and Volume in Highly Trained and Elite Distance Runners: A Systematic Review"
- "Training Characteristics of World-Class Distance Runners" "Integration of Scientific Literature and Results-Proven Practice" sportsmedicine-open.springeropen.com doi
- Rosenblat 2019 "Polarized vs. Threshold Training Intensity Distribution on Endurance Sport Performance" systematic review meta-analysis
- Rosenblat network meta-analysis individual participant data training intensity distribution "maximal oxygen uptake and time-trial performance" Sports Medicine
- Silva Oliveira Boppre Fonseca 2024 "Comparison of Polarized Versus Other Types of Endurance Training Intensity Distribution" meta-analysis Sports Medicine
- "29863593" polarized threshold training Rosenblat (failed attempt to check a PMID)
- Burnley Bearden Jones "Polarized Training Is Not Optimal for Endurance Athletes" Medicine Science Sports Exercise 2022
- Foster Casado Esteve-Lanao Haugen Seiler "Polarized Training Is Optimal for Endurance Athletes" 2022 pubmed
- Casado Hanley Santos-Concejero Ruiz-Pérez "World-Class Long-Distance Running Performances Are Best Predicted by Volume of Easy Runs"
- Casado Foster Bakken Tjelta 2023 "lactate-guided threshold interval training" high-volume low-intensity "next step" distance running
- mdpi ijerph 2023 20 5 3782 Casado lactate-guided threshold interval training
- "World-Class Long-Distance Running Performances Are Best Predicted by Volume of Easy Runs" abstract runners training logs tempo short interval
- Billat 2003 "Training and bioenergetic characteristics in elite male and female Kenyan runners" Med Sci Sports Exerc
- Billat Demarle 2001 "Physical and training characteristics of top-class marathon runners"
- Karp 2007 "Training characteristics of qualifiers for the U.S. Olympic Marathon Trials" IJSPP
- Tjelta "Three Norwegian brothers all European 1500 m champions: What is the secret?" International Journal of Sports Science & Coaching
- Tjelta Tønnessen Enoksen "A case study of the training of nine times New York Marathon winner Grete Waitz"
- Enoksen Tjelta Tjelta 2011 "Distribution of training volume and intensity of elite male and female track and marathon runners"
- Jones AM 2006 "The physiology of the world record holder for the women's marathon" International Journal of Sports Science & Coaching
- Stellingwerff 2012 "Case study: Nutrition and training periodization in three elite marathon runners"
- Ingham Fudge Pringle 2012 "Training distribution, physiological profile, and performance for a male international 1500-m runner"
- Kenneally Casado Santos-Concejero 2018 "The Effect of Periodization and Training Intensity Distribution on Middle- and Long-Distance Running Performance: A Systematic Review"
- Kenneally 2021 "Training intensity distribution analysis by race pace vs. physiological approach in world-class middle- and long-distance runners"
- Sylta Tønnessen Seiler 2014 "From heart-rate data to training quantification: a comparison of 3 methods of training-intensity analysis"
- Kenneally 2018 IJSPP systematic review periodization training intensity distribution middle long distance running "pyramidal" "polarized" abstract results studies included
- Bellinger Arnold Minahan 2020 "Quantifying the Training-Intensity Distribution in Middle-Distance Runners: The Influence of Different Methods of Training-Intensity Quantification"
- Treff Winkert Sareban Steinacker Sperlich 2019 "The Polarization-Index: A Simple Calculation to Distinguish Polarized From Non-polarized Training Intensity Distributions"
- REFUSED (budget exhausted): "Training-intensity Distribution on Middle- and Long-distance Runners: A Systematic Review" Int J Sports Med 2022 Campos
- REFUSED (budget exhausted): Jamnick Pettitt Granata Pyne Bishop 2020 "An Examination and Critique of Current Methods to Determine Exercise Intensity" Sports Medicine
- REFUSED (budget exhausted): Faude Kindermann Meyer 2009 "Lactate threshold concepts: how valid are they?" Sports Medicine

## Europe PMC / Crossref lookups (targeted verification)
- Europe PMC: `EXT_ID:20861519 AND SRC:MED` succeeded. These failed with 429: `AUTH:"Seiler S" AND (TITLE:"intensity distribution" OR TITLE:"best practice")`, `EXT_ID:16430681 OR EXT_ID:15758693 OR EXT_ID:24550842`, `AUTH:"Rosenblat MA"`, and `EXT_ID:36900796 OR EXT_ID:35136001 OR EXT_ID:19255456`. Two multi-title OR queries were rejected with 403 (URL too long).
- Crossref query.bibliographic: Rosenblat polarized threshold; Esteve-Lanao 2007; Billat 2001; Bellinger 2020; Jones 2006 women's marathon. These failed with an error or 429: Foster 2022; Campos 2022 TID review; Jamnick 2020.
- Crossref works/{doi} succeeded for: 10.1007/s40279-024-02149-3, 10.1007/s40279-024-02034-z, 10.1111/j.1600-0838.2004.00418.x, 10.3389/fphys.2014.00033, 10.1123/ijspp.7.2.193, 10.1123/ijsnem.22.5.392, 10.1249/01.MSS.0000053556.59992.A9. It errored for 10.1249/MSS.0000000000002871, 10.1260/174795406777641258 and 10.1055/a-1559-3623.

## Fields flagged as not fully verified in F.json
- campos-2022-tid-middle-long-distance-runners-review: the author list is NOT verified (the first author "Campos" is inferred). The title, journal, DOI and abstract are verified.
- kenneally-2021-tid-race-pace-vs-physiological-world-class: the full author list is not verified (recorded as "Kenneally M, et al.").
- foster-2022-polarized-training-optimal: recorded as "Foster C, et al." (authorship confirmed only through the reply title "Response to Foster and colleagues").
- PMIDs are null wherever one was not seen. Likely PMIDs exist for Seiler 2006, Stöggl 2014, Esteve-Lanao 2007, Rosenblat 2019 and others; fill them in once Europe PMC is reachable.
- Casado 2023 (MDPI) and the Stirling/AUT/Griffith repository copies may carry CC licences, but no licence was seen, so they are recorded as free-to-read with license null.

## Candidates surfaced but NOT catalogued (and why)
- Sperlich, Matzka & Holmberg 2023, "The proportional distribution of training by elite endurance athletes at different intensities during different phases of the season" (Frontiers in Sports and Active Living; PMC10641476 seen in results). Abstract not read before the budget ran out. Strong candidate for intensity-distribution.
- MSSE 2022 debate rebuttals: "Polarized training is optimal for endurance athletes: Response to Burnley, Bearden, and Jones" (54(6):1035-1037, DOI 10.1249/MSS.0000000000002923, landing record seen but no abstract) and "Polarized training is not optimal for endurance athletes: Response to Foster and colleagues". Left out to avoid padding; add if the review covers the full debate.
- Van Hooren, Balamouti & Zanini 2025, "A case report of the female world record holder from 1,500 m to the marathon in the 75+ age category" (J Appl Physiol 138(2):603-611, DOI 10.1152/japplphysiol.00974.2024; Crossref record only). Abstract not read. Candidate for the special-populations scope.
- Tjelta, "A longitudinal case study of the training of the 2012 European 1500m track champion" (lida record 4031785). Not read.
- "Training intensity distribution and performance of a recreational male endurance runner. A case report" (University of A Coruña portal). Not read.
- Seiler & Tønnessen 2009, "Intervals, Thresholds, and Long Slow Distance: the Role of Intensity and Duration in Endurance Training" (Sportscience; PDF link seen in results). Not read.
- González-Ravé 2022 swimmers TID systematic review; trained-cyclist TID reviews; an animal (Wistar rat) polarized vs threshold study: outside running scope.
- PubMed 29863593 appeared in results for the Rosenblat 2019 query, but which article it is could not be confirmed, so it was not used.

## Brief-named items still to verify and catalogue (follow-up pass; no identifiers recorded here)
Intensity distribution / zones:
- Jamnick et al. 2020, critique of methods to determine exercise intensity (Sports Med)
- Faude, Kindermann & Meyer 2009, lactate threshold concepts
- Mann, Lamberts & Lambert 2013, methods of prescribing relative intensity
- Iannetta et al. 2020, critical evaluation of exercise prescription methods
- Meyler et al. 2023, variability in responses to threshold- vs %VO2max-anchored prescription
- Poole et al. 2016, critical power as a fatigue threshold
- Hofmann & Tschakert 2017, intensity- and duration-based options to regulate endurance training
- Seiler & Tønnessen 2009 (Sportscience)
- Zinner et al. 2018, mesocycles with different TID in recreational runners
- Festa et al. 2020, TID in recreational runners
- Filipas et al. 2022, pyramidal vs polarized in well-trained runners
- Emig & Peltonen 2020, real-world big training data
- Doherty et al. 2020, meta-regression of training determinants of marathon performance
- Boullosa et al. 2020, factors affecting training in recreational endurance runners
- Midgley et al. 2006 and 2007 (Sports Med)
- Casado et al. 2020, deliberate practice in Kenyan vs Spanish runners
- Tønnessen et al. 2014, "The road to gold" (PLoS One)

Coaching and training principles:
- Periodization: Issurin 2010 and 2019 with Kiely et al.'s comment; Kiely 2012 and 2018; Mujika et al. 2018; Mølmen et al. 2019 (block periodization meta-analysis); Afonso et al. 2017; Cunanan et al. 2018 (General Adaptation Syndrome); Sylta et al. 2016; Rønnestad et al. 2014
- Fitness-fatigue / impulse-response: Calvert, Banister et al. 1976; Morton et al. 1990 (running); Busso 2003; Busso et al. 1997; Hellard et al. 2006; Clarke & Skiba 2013; Wallace, Slattery & Coutts 2014 (runners); Imbach et al. 2022; Vermeire et al. 2022
- Individualization and response heterogeneity: Mann, Lamberts & Lambert 2014; Pickering & Kiely 2019; Montero & Lundby 2017; Hecksteden et al. 2015; Bonafiglia et al. 2016
- Autoregulation / HRV-guided training: Vesterinen et al. 2016; Nuuttila et al. 2022 (recreational runners); Kiviniemi et al. 2007; da Silva et al. 2019; Düking et al. 2021 (meta-analysis)
- Qualitative studies of endurance coaches' planning and the coach-athlete relationship: none found yet (no searches possible)
- Interval-training programming: Laursen & Jenkins 2002; Buchheit & Laursen 2013, parts I and II
- Kipchoge: no peer-reviewed training case study was located before the budget ran out
- Books to record as citations only: Laursen & Buchheit, *Science and Application of High-Intensity Interval Training* (Human Kinetics); Daniels, *Daniels' Running Formula* (Human Kinetics); Lydiard & Gilmour, *Running with Lydiard*; Bompa & Buzzichelli, *Periodization: Theory and Methodology of Training*; Mujika, *Endurance Training: Science and Practice*
