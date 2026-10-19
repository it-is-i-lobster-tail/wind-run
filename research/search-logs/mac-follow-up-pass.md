# Mac follow-up pass (thin topics and unverified leads)

This pass ran on a machine with direct access to the Europe PMC REST API and OpenAlex, after the nine cloud searches. It had two jobs: check the "unverified leads" and "known gaps" listed at the end of the other search logs, and add sources to the thinnest topics (coaching principles, beginners, event preparation, special populations, strength and cross-training, environment).

## Method

- Searches used the Europe PMC REST search (`resultType=core`, which returns the abstract), sorted by citation count where useful. OpenAlex was used to look up records that Europe PMC lacked.
- Every new record's title, authors, year, venue, DOI, PMID and PMCID come from the Europe PMC record. Nothing was typed from memory.
- Each candidate's abstract was read before it was added, and the `summary` and `relevance` fields were written from that abstract. For two IOC pregnancy papers with no deposited abstract, the opening text in the OpenAlex record was used, and the summary says so.
- New records were checked against existing records by DOI, PMID and normalised title. Each record's `found_via` starts with "Mac follow-up pass:" followed by the query.
- Priorities matched the main pass: systematic reviews and meta-analyses, RCTs, large cohorts, consensus statements and guidelines, landmark papers and recent work. Studies that contradict common advice were included on purpose (for example, placebo-controlled altitude trials and run/walk marathon results).

## Queries (Europe PMC unless noted)

Environment (heat, altitude, cold, pollution, terrain):
- `(TITLE:"heat acclimation" OR TITLE:"heat adaptation" OR TITLE:"heat stress") AND (exercise OR performance OR athletes) AND (review OR meta-analysis) AND PUB_YEAR:[2014 TO 2026]`, sorted by citations
- `(TITLE:"heat acclimation" ...) AND (meta-analysis OR systematic review OR consensus)`
- `altitude training OR live high OR hypoxic training` AND `(endurance OR runners OR sea-level performance)` AND `(meta-analysis OR systematic review OR review OR placebo)`
- Lead checks by author and title: Roberts 2021 (ACSM heat illness consensus), Racinais 2022 (Doha), Mantzios 2022 (1258 races), Knechtle 2019 (Boston weather), Vihma 2010, Bonetti & Hopkins 2009, Levine & Stray-Gundersen 1997, Chapman 1998, Siebenmann 2012, Lundby & Robach 2016, Mujika 2019, Girard 2020, Marr & Ely 2010, Giles & Koehle 2014, Castellani 2006 (ACSM cold), Minetti 2002, Vernillo 2017, Wehrlin & Hallén 2006, ACSM 2007 exertional heat illness
- `(cooling OR precooling) AND (meta-analysis OR systematic review) AND (exercise OR performance)`
- `treadmill AND overground AND running AND (systematic review OR meta-analysis OR comparable)`; `TITLE:"1% treadmill grade"`
- `(heat OR hot) AND (marathon OR road race OR runners) AND (pacing OR performance OR exertional heat)`

Beginners and adherence:
- Lead checks: Menheere 2020, Janssen 2017, Dallinga 2018, Pereira 2021, Grunseit 2020, Stevinson 2014, Quirk 2021
- `TITLE:"couch to 5k" OR "couch-to-5k" OR C25K` (gap: evaluation of Couch to 5K)
- `(TITLE:"novice runners" OR TITLE:"beginning runners") AND PUB_YEAR:[2015 TO 2026]`, sorted by citations
- `parkrun AND (scoping review OR systematic review)`
- `(running OR runners) AND osteoarthritis AND (meta-analysis OR systematic review)`
- `(wearable OR activity tracker) AND physical activity AND (umbrella review OR meta-analysis) AND PUB_YEAR:[2018 TO 2026]`
- `(habit formation OR habit) AND (exercise OR physical activity) AND (review OR real world)`

Coaching and training principles:
- Lead checks: Issurin 2010, Kiely 2012 and 2018, Mujika 2018, Mølmen 2019, Afonso 2017, Cunanan 2018, Sylta 2016, Busso 2003, Hellard 2006, Clarke & Skiba 2013, Wallace 2014, Imbach 2022, Vermeire 2022, Pickering & Kiely 2019, Hecksteden 2018, Bonafiglia 2016
- `(coach OR coaches) AND (endurance OR running OR runners) AND (training OR periodization OR planning) AND PUB_YEAR:[2010 TO 2026]` (gap: studies of endurance coaches)
- `(e-coach OR virtual coach OR digital coach OR personalized training) AND (running OR runners)`

Event preparation, tapering and pacing:
- Lead checks: Spilsbury 2015/2019, Houmard 1994, Mujika 2010, Damsted 2019 (ProjectRun21), Santos-Lozano 2014, Díaz 2018, Buman 2008 (not found; Grivas 2026 review added instead)
- `(taper OR tapering) AND (runners OR marathon OR running OR endurance)`, sorted by citations
- `pacing AND (marathon OR half-marathon OR 10 km OR 5 km) AND PUB_YEAR:[2012 TO 2026]`, sorted by citations
- `(pacing OR even pace OR negative split) AND (systematic review OR meta-analysis OR review)`
- `(warm-up OR priming) AND (running performance OR endurance performance OR time trial)`
- `(recovery OR muscle damage) AND marathon AND (time course OR recovery after)`

Special populations:
- Lead checks: McKean 2006, Fell & Williams 2008, Brenner 2024 (AAP), Besson 2022, Elliott-Sale 2020, Mottola 2018, Bø 2016-2018 (IOC pregnancy series), Riddell 2017, Sims 2023, Newman 2021
- `(masters OR older OR aging) AND (runners OR running) AND (injury OR injuries)`
- `urinary incontinence AND (runners OR running)`; `(running OR jogging) AND (pregnancy OR pregnant)`
- `exercise-induced bronchoconstriction AND (guideline OR practice parameter)`

Strength and cross-training:
- `deep-water running OR deep water running OR aqua jogging OR water running` (verifying Reilly 2003); Bushman 1997; Tanaka 1994; Mutton 1993; Doma 2017/2019
- `plyometric AND (running economy OR distance runners OR running performance)`, sorted by citations
- `(cross-training OR cycling training OR elliptical OR anti-gravity treadmill OR lower body positive pressure) AND (runners OR running)`
- `(strength training OR resistance training) AND runners AND PUB_YEAR:[2018 TO 2026]`, sorted by citations
- Skovgaard 2014 (speed endurance plus strength)

Other topics' leads: Ruuska 2012, Wilson 2020 (COVID-19 return to play), Johnston 2019, van Poppel 2016 and 2021, Nieman 1990, Malisoux 2022, Eckard 2018, Marti 1988, Carrard 2022, Aubry 2015, Davis 2020 (massage), Malta 2021 (cold-water immersion), Gellish 2007, Scherr 2013, Borresen 2009, Navalta 2020, Sloth 2013, Festa 2019, Zinner 2018, Filipas 2022, Tønnessen 2014, Pettitt 2012, Quinn 2011, Swain 1997.

## Leads that were already catalogued

Walsh 2021 (sleep consensus), Faude 2009, Jamnick 2020, Iannetta 2020, Mann 2013, Hecksteden 2015, Vesterinen 2013/2016, Kiviniemi 2007, Manresa-Rocamora 2021, Buchheit & Laursen 2013 (parts I and II), Laursen & Jenkins 2002, Casado 2021/2022, Kenneally 2021, Johnston 2018, Wang 2023, Smyth 2021, Toresdahl 2022, Fokkema 2019, Kluitenberg 2016, Bertelsen 2018, Eihara 2022, Llanos-Lagos 2024, Toresdahl 2020, Van Hooren 2020, Rosenblat 2025.

## Leads not found or not added

- Not found in Europe PMC with author and title searches: Calvert, Banister et al. 1976 (IEEE journal, not indexed); Seiler & Tønnessen 2009 (Sportscience, not indexed); Buman et al. 2008 ("hitting the wall"); Bradbury et al. 2020 (reverse linear periodisation); Vandewalle 2018; Ivarsson et al. 2017 (psychosocial meta-analysis); Walter et al. 1989 (Ontario cohort); Tenforde et al. 2013 (adolescent stress fractures); Emig & Peltonen 2020.
- Found but not added (overlap, weak design or low relevance): Brickwood 2019 (overlaps Laranjo 2021), Benjamin 2019 (abstract garbled in the record), Girard 2020 (hypoxic methods for elite athletes), Imbach 2022 (speed skaters), Muñoz-Pérez 2020, Stenerson 2023, Doering 2016, Hostrup & Bangsbo 2017, Ferley 2016.
- Not searched in this pass: Koplan 1982, Hansen 2014 and Atkinson 2011 (in-race carbohydrate), Pedlar 2018 (iron), Schwellnus 2019 (SAFER VIII), Stults-Kolehmainen 2014, Bartholomew 2008, Kim 2021 (JAMA Cardiology), Kaushal & Rhodes 2015, Lally 2010.
