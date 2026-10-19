# Search log - researcher E (speed-development, strength-and-cross-training, physiology-and-performance-determinants)

## Engines / databases used
- WebSearch (standard mode) - main discovery engine
- Europe PMC REST API (via WebFetch) - heavily rate-limited (HTTP 429) during this session; used only when it answered
- OpenAlex API (api.openalex.org, via WebFetch) - metadata (DOI/PMID/PMCID/OA/license); also intermittently rate-limited (HTTP 429)
- Semantic Scholar Graph API (via WebFetch) - IDs + TLDR when abstracts elided
- Publisher / repository / index landing pages (Springer, Frontiers, Termedia JHK, PEDro, SPONET/LIDA, university repositories, DOAJ, Epistemonikos)
- NCBI E-utilities: blocked (robots disallowed); PubMed/PMC pages not fetched (captcha), only IDs from search-result URLs

## Queries run (one per line)
- WebSearch: Milanović Sporiš Weston 2015 effectiveness of high-intensity interval training and continuous endurance training for VO2max improvements meta-analysis
- Europe PMC: TITLE:"high-intensity interval training" AND TITLE:"VO2max" AND AUTH:"Milanović" (429 rate-limited)
- Europe PMC: DOI:10.1007/s40279-015-0365-0 (ok)
- Europe PMC: TITLE:"interval training for performance" AND AUTH:"Billat" (429)
- WebSearch: Billat 2001 "Interval training for performance: a scientific and empirical practice" Part I aerobic interval training Sports Medicine
- WebSearch: pubmed Billat interval training for performance scientific empirical practice middle- and long-distance running aerobic interval training
- WebSearch: systematic review meta-analysis high-intensity interval training running performance runners 2023 OR 2024 OR 2025
- WebSearch: Wiesinger Stöggl Hopkins "Meta-analyses of the effects of high-intensity interval training in elite athletes" part II
- Europe PMC: DOI:10.3389/fphys.2024.1486526 OR DOI:10.3389/fphys.2024.1486570 (429)
- NCBI E-utilities esummary (blocked by robots)
- OpenAlex: works/doi:10.3389/fphys.2024.1486526 (ok)
- OpenAlex: filter=title.search:interval training for performance scientific empirical practice (ok)
- OpenAlex: filter=doi: Buchheit & Laursen I/II, Laursen & Jenkins (ok)
- Semantic Scholar: paper/DOI:10.2165/00007256-200232010-00003 (ok, abstract elided)
- WebSearch: Wen Utesch 2019 "Effects of different protocols of high intensity interval training for VO2max improvements in adults"
- WebSearch: Gunnarsson Bangsbo 2012 "10-20-30 training concept improves performance and health profile in moderately trained runners"
- WebSearch: Iaia Bangsbo 2010 "Speed endurance training is a powerful stimulus..."
- WebSearch: Rosenblat Perrotta Thomas 2020 "high-intensity interval training versus sprint interval training on time-trial performance"
- WebSearch: Rosenblat 2021 "Programming Interval Training to Optimize Time-Trial Performance"
- WebSearch: "sprint interval training" physical performance systematic review meta-analysis Hall Aspe Swinton JSCR
- WebSearch: Gist Fedewa Dishman Cureton 2014 "Sprint interval training effects on aerobic capacity"
- WebSearch: García-Pinillos 2017 "How does high-intensity intermittent training affect recreational endurance runners?"
- WebSearch: Laursen Jenkins 2002 "The scientific basis for high-intensity interval training..."
- WebFetch (publisher/repository pages, no search): Springer pages for Buchheit & Laursen I/II, Blagrove 2018, Beattie 2014, Denadai 2017, Eihara 2022, Schumann 2022 (ok); Springer pages for Laursen & Jenkins 2002, Jones & Vanhatalo 2017, Maunder 2021 (fetch errors)
- WebSearch: Balsalobre-Fernández Santos-Concejero Grivas 2016 "Effects of Strength Training on Running Economy in Highly Trained Runners"
- WebSearch: Rønnestad Mujika 2014 "Optimizing strength training for running and cycling endurance performance: A review"
- WebSearch: Llanos-Lagos ... 2024 strength training methods middle/long-distance runners meta-analysis -> NOT RUN: shared WebSearch budget (200/turn) exhausted at this point
- Europe PMC: AUTH:"Llanos-Lagos C" (429 rate-limited)
- OpenAlex single-work DOI lookups (ok): Joyner & Coyle 2008; Bassett & Howley 2000; Joyner 1991; Jones 2021; Jones 2024; Maunder 2021 (no abstract in record)
- OpenAlex filter=doi batch lookups (429 rate-limited twice; URL-length limit hit once)
- Semantic Scholar DOI lookup Joyner & Coyle (fetch error)
- PLOS ONE pages: Bacon 2013; Hatle 2014 (ok)
- physiology.org pages (Gunnarsson 2012 full text; Jones 2021 PDF): fetch errors
- Europe PMC EXT_ID:33886100 -> refused: shared WebFetch budget (400/hour) exhausted

## Session constraints encountered
- Shared WebSearch budget (200 calls per turn across all 9 researchers) ran out after ~25 of my searches; further discovery relied on known landmark papers verified by DOI lookups and publisher pages.
- Shared WebFetch budget (400/hour across all agents) was exhausted repeatedly; Europe PMC and OpenAlex list endpoints returned HTTP 429 most of the time.

## Later verification calls (after budget refills)
- OpenAlex single-work DOI lookups (ok, abstracts read from inverted index): Bouchard 1999 (HERITAGE); Montero & Lundby 2017; Helgerud 2007; Paavolainen 1999; Holloszy & Coyle 1984; Montero 2015; Lauersen 2014; Støren 2008; McLaughlin 2010; Poole 2016; MacInnis & Gibala 2017
- OpenAlex DOI 10.3390/ijerph20053782 (Casado 2023) -> refused: shared WebFetch budget exhausted again
- OpenAlex single-work DOI lookups (ok): Saunders 2004 (no abstract); Barnes & Kilding 2015 (Sports Med Open); Casado 2023; Smyth 2022; Poole 2021; Eyestone 1993; Toresdahl 2020; Pettitt 2016; Barnes 2013; Atkinson & Batterham 2015; Ross 2019; Haugen 2022; Wilson 2012; Jones 2019; Lundby 2017; Vikmoen 2016; Billat 1999; Laursen 2010; Llanos-Lagos 2024 (x2); Beattie 2017; Vollaard 2017; Lauersen 2018
- OpenAlex DOI/PMID lookups for missing IDs/licences (ok): García-Pinillos 2017; Blagrove 2018; Eihara 2022; Schumann 2022; Wiesinger 2024 part II; Gist 2014 (pmid:24129784); Wen 2019; Rosenblat 2021; Hall 2023; Beattie 2014; Rønnestad & Mujika 2014; Denadai 2017; Bacon 2013; Hatle 2014; Gunnarsson 2012
- Semantic Scholar Graph API DOI lookups (ok): Jones 2021 (abstract); Maunder 2021 (TLDR only); Saunders 2004 (TLDR only); Midgley 2007 (TLDR only); Faude 2009 (TLDR only)
- Springer landing pages: Saunders 2004 (fetch error); Barnes & Kilding 2015 Strategies (ok); Jamnick 2020 (fetch error)
- Europe PMC (all HTTP 429): EXT_ID:33886100 OR EXT_ID:15233599 OR EXT_ID:33151776; TITLE:"deep water running" OR TITLE:"deep-water running"; TITLE:"cross-training" AND (runners OR running)

## Notable candidates rejected / not catalogued (and why)
- Reilly, Dowzer & Cable 2003 "The physiology of deep-water running" (J Sports Sci): DOI from memory resolved to an unrelated rowing paper; correct record could not be verified without search (budget exhausted) -> not catalogued.
- Seiler et al. 2013 "Adaptations to aerobic interval training: interactive effects of exercise intensity and total work duration" (SJMSS): DOI from memory resolved to Vesterinen et al. 2013 instead (catalogued, as it fits individual-response variability); Seiler 2013 itself unverified -> not catalogued.
- Jones & Vanhatalo 2017 "The 'Critical Power' concept" (Sports Med Suppl) and Jamnick et al. 2020 (exercise-intensity methods critique): Springer pages failed to load and no API record was retrieved -> not catalogued (Poole 2016, Jones 2019, Pettitt 2016 cover critical speed).
- Tanaka 1994 (cross-training transfer), Mutton 1993 (run vs cycle/run training), Wilber 1996 and Bushman 1997 (deep-water running), Doma 2017 (concurrent training and endurance performance): could not be located/verified after the shared WebSearch budget ran out and Europe PMC kept returning 429 -> not catalogued.
- Sloth 2013 SIT meta-analysis, Esfarjani & Laursen 2007, Ferley 2013 (hill intervals), Skovgaard 2014 / Vorup 2016 (speed endurance + strength in runners), Hostrup & Bangsbo 2017, Coyle 1995, Foster & Lucia 2007, Jones & Carter 2000, Granata 2018: not attempted/verified because of fetch-budget limits; topics are partly covered by catalogued sources (Gist 2014, Vollaard 2017, Hall 2023, Barnes 2013, Iaia & Bangsbo 2010, MacInnis & Gibala 2017).
- Search-result items not opened (budget): EBSCO record "High-intensity interval vs moderate-intensity continuous training in endurance runners: a systematic review..."; Physiological Reports (May 2025) DOAJ record; "systematic review and cluster analysis approach of 103 studies" (Mount Sinai); LIDA record "Effects of short sprint interval training on aerobic and anaerobic indices".
- Press/blog pages (ScienceDaily, Medical News Today, FastTalk Labs, Substack, triathlete.com, getfitcraft) seen in results: not peer-reviewed -> excluded.
