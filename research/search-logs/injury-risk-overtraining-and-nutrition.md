# Search log - researcher D (injury risk & training errors; overtraining, recovery & sleep; nutrition & fueling)

## Access notes (tool limits hit during this session)
- Europe PMC REST API: first call (EXT_ID:17473005) returned HTTP 429 via the proxy; a batched OR query was rejected for URL length; a later retry with a 4-PMID core query also returned HTTP 429. Europe PMC therefore contributed no records.
- WebSearch: only 2 searches ran before the shared per-turn WebSearch budget (200 calls across all agents) was exhausted; discovery afterwards relied on known landmark literature plus OpenAlex bibliographic lookups.
- WebFetch: the shared budget (400/hour across all agents) was exhausted several times (HTTP 403); OpenAlex and Crossref also returned HTTP 429 on some calls, and NCBI E-utilities refused (robots disallowed). Fetches were batched (up to 8 PMIDs per OpenAlex call) and rationed with pauses.
- link.springer.com/article/10.1007/s40279-016-0636-4 returned HTTP 429 once (abstract read instead from the Amsterdam UMC repository page); other Springer pages worked.
- Semantic Scholar Graph API returned a fetch error; not used.
- Main verification route: OpenAlex API (works?filter=pmid:...|... or doi:...|... with select=..., and works/pmid:/doi: lookups) for title, authors, venue, year, DOI, PMID, PMC location, OA status/licence and reconstructed abstracts; publisher or repository landing pages (Springer, BJSM, Nature, Amsterdam UMC Pure) for abstracts and licence statements. PMIDs/PMCIDs were recorded only when they appeared in an API record or a search-result URL; one OpenAlex PMID that conflicted with the publication date (Jeukendrup 2014) was left null.
- Summaries for some landmark papers whose API record lacked an abstract (e.g., Halson & Jeukendrup 2004, Mountjoy 2014, Heikura 2018, Barrack 2014, Kim 2012, Lauersen 2014, Nattiv 2007, De Souza 2014, Sim 2019, Guest 2021, Jager 2017, Goulet 2011, Jeukendrup 2014, Wang 2020, Warden 2021, several nutrition position stands) were written from the verified record plus prior knowledge of these widely cited papers; the found_via field flags where numbers need confirming in the in-depth analysis.

## Discovery strategy
- Because the shared WebSearch budget ran out after two searches, candidates came mainly from the landmark papers named in the brief plus the researcher's knowledge of the systematic-review, consensus and RCT literature on running injury, overtraining/RED-S/sleep and endurance nutrition (2015-2026 prioritised, classics retained). Every catalogued item was then individually confirmed against an OpenAlex API record and/or a publisher/repository landing page before cataloguing; items that could not be confirmed were left out (listed at the end).

## Queries run (engine - query)
- Europe PMC REST - query=EXT_ID:17473005 AND SRC:MED (HTTP 429, abandoned)
- Europe PMC REST - EXT_ID OR-batch of 8 PMIDs (rejected: URL too long)
- OpenAlex API - works/doi:10.1136/bjsm.2006.033548 (van Gent 2007)
- OpenAlex API - filter=pmid:25951917|33862272|25808527|22389869 (Videbaek, Kakouris, Yamato, Nielsen 2012)
- OpenAlex API - filter=pmid:22389869|28329441|26758673; works/pmid:22389869 (full abstract)
- WebSearch - "How much running is too much" high-risk running sessions 5200 runners cohort BJSM 2025
- OpenAlex API - search="how much running is too much high-risk running sessions" (Frandsen 2025; Soligard 2016)
- OpenAlex API - filter=pmid:15126720|24809248|27785775 (Hreljac, Saragiotto, Hulme)
- Springer landing page - 10.1007/s40279-014-0194-6 (Saragiotto abstract)
- OpenAlex API - filter=pmid:25155475|17940147|32502973 (Nielsen 2014, Buist 2008, Impellizzeri 2020)
- OpenAlex API - filter=pmid:25706955|33433864|25103133; pmid:25103133|35484131 (van der Worp, Hollander, Warden, Hoenig)
- Semantic Scholar Graph API - PMID:22389869 (fetch error)
- WebSearch - Nielsen Buist Sorensen Lind Rasmussen 2012 "Training errors and running related injuries: a systematic review" (found Damsted 2018 PMID 30534459 / PMC6253751)
- nature.com landing page - s41572-022-00352-y (Hoenig 2022 abstract)
- BJSM landing page - bjsm.bmj.com/content/50/17/1030 (Soligard 2016 summary)
- Crossref API - works/10.1007/s40279-016-0636-4 (no abstract)
- Amsterdam UMC Pure page - Hulme 2017 abstract
- OpenAlex API - filter=doi:10.1136/bjsports-2018-099744|10.2519/jospt.2021.9673 (Fokkema 2019, Desai 2021)
- OpenAlex API - filter=doi:10.4085/1062-6050-0195.21|10.1136/bjsports-2015-094828 (Fredette, Wright)
- OpenAlex API - filter=pmid:30534459|29895234 (Damsted 2018, Ramskov 2018)
- OpenAlex API - filter=pmid:22827721|25851584 (Lopes 2012, Kluitenberg 2015)
- OpenAlex API - filter=pmid:24620037|29773536|37752011; works/doi:10.1136/bjsports-2023-106994 (Mountjoy 2014/2018/2023)
- BJSM landing page - bjsm.bmj.com/content/52/11/687 (Mountjoy 2018 full text)
- OpenAlex API - filter=pmid:23247672|23016079|15571428 and pmid:23016079|15571428 (Meeusen, Kreher, Halson)
- OpenAlex API - filter=pmid:33144349|25028798|9662690; works/pmid:25028798 (Walsh 2021, Milewski 2014, Foster 1998)
- OpenAlex API - filter=pmid:25315456|35708888|29352373; works/pmid:35708888 (Fullagar, Craven, Bonnar)
- Springer landing pages - 10.1007/s40279-014-0260-0 (Fullagar), 10.1007/s40279-017-0832-x (Bonnar)
- OpenAlex API - filter=pmid:27535991|29637836|34181189; works/pmid:29637836 (Schwellnus 2016, Walsh 2018)
- OpenAlex API - works/pmid:34181189 (Stellingwerff 2021) - rejected: shared fetch budget exhausted
- WebSearch - New York City Marathon runners training patterns associated with injury prospective cohort Toresdahl - NOT RUN: shared WebSearch budget (200/turn) exhausted
- OpenAlex API - filter=pmid:26891166|21660838|24791914|28332114|17277604|26102445|15829535|28642676 (Thomas, Burke 2011, Jeukendrup 2017, Sawka, Hew-Butler, Almond; 24791914 and 28642676 not returned)
- OpenAlex API - filter=pmid:33388079|5584523|7333741|28012184|30747558|32245088|29252050|20975938 (Bergstrom, Sherman, Burke 2017, Burke 2019, Logue, Heikura, Rapoport; 33388079 not matched)
- OpenAlex API - filter=pmid:21775906|20667899|29368181|29540367|29453741|24951297|30926628|28589631 (Pfeiffer, Kenefick, Maughan, Impey, Stellingwerff & Cox, Grgic, Costa; 20667899 not matched)
- OpenAlex API - filter=pmid:34181189|32064575|25134000|29755363|29345524|27406221|28785411|26423706 (Stellingwerff 2021, Bellinger, Aubry, Dupuy, Kellmann, Ivarsson, Cadegiani, Saw)
- OpenAlex API - filter=doi:10.1186/s12970-020-00383-4|10.1186/s12970-017-0177-8|10.1007/s40279-014-0148-z (Guest 2021, Jager 2017, Jeukendrup 2014) - first attempt rejected: shared fetch budget exhausted
- OpenAlex API - filter=pmid:31055680|17909417|24463911|24567250|22236223|24100287|2266764|25200666 (Sim 2019, Nattiv 2007, De Souza 2014, Barrack 2014, Kim 2012, Lauersen 2014, Nieman 1990, Halson 2014) - first try: fetch budget exhausted; second try: OpenAlex HTTP 429 (rate limited; URL not retried)
- NCBI E-utilities efetch (same 8 PMIDs, abstracts) - refused (robots disallowed)
- Europe PMC REST - EXT_ID:31055680 OR 17909417 OR 24463911 OR 24567250 (core) - refused: shared fetch budget exhausted
- Europe PMC REST - same 4-PMID core query retried after budget refill - HTTP 429 (rate limited; not retried)
- Crossref API - filter=doi:10.1186/s12970-020-00383-4,doi:10.1186/s12970-017-0177-8,doi:10.1007/s00421-019-04157-y (Guest 2021, Jager 2017, Sim 2019) - HTTP 429 (rate limited; not retried)
- OpenAlex API - filter=pmid:17909417|31055680|24567250|24100287|22236223|24463911|25200666 (Nattiv 2007, Sim 2019, Barrack 2014, Lauersen 2014, Kim 2012, De Souza 2014, Halson 2014) - success after rate-limit pause
- OpenAlex API - filter=doi:10.1186/s12970-020-00383-4|10.1186/s12970-017-0177-8|10.1136/bjsm.2010.077966 (Guest 2021, Jager 2017, Goulet 2011)
- OpenAlex API - filter=doi:10.1007/s40279-014-0148-z|10.1007/s40279-020-01280-1|10.1007/s11914-021-00666-y (Jeukendrup 2014, Wang 2020, Warden 2021)
- OpenAlex API - filter=doi:10.1186/s12970-021-00435-3|10.1371/journal.pone.0157406 (Gejl & Nybo 2021, Kato 2016) - HTTP 429 (rate limited; URL not retried; both later verified via the separate queries below)
- OpenAlex API - filter=doi:10.1002/14651858.CD001256.pub2|10.1177/0363546518773755 (Yeung 2011 Cochrane, Messier 2018 TRAILS; abstracts)
- OpenAlex API - filter=doi:10.1186/s12970-021-00435-3|10.1136/bjsports-2022-106328 (Gejl & Nybo 2021, Hoenig 2023; abstracts)
- OpenAlex API - filter=doi:10.1371/journal.pone.0157406|10.1007/s40279-018-0939-8 (Kato 2016, Southward 2018)
- OpenAlex API - filter=doi:10.1139/apnm-2016-0453|10.1111/sms.12735 (Costa 2017 gut-training RCT, von Rosen 2017 sleep/diet and injury) - HTTP 429 (rate limited; URL not retried)
- OpenAlex API - works/doi:10.1111/sms.12735 (von Rosen 2017; abstract)
- OpenAlex API - works/doi:10.1139/apnm-2016-0453 (Costa 2017 gut-training RCT; abstract)
- OpenAlex API (discovery) - search='running related injury risk factors', filter publication_year:2024-2026,type:review, sort cited_by_count - results irrelevant (generic highly cited reviews); refined below
- OpenAlex API (discovery) - filter=title.search:running injury,publication_year:2023-2026 sorted by citations - HTTP 429 (rate limited; not retried). Session stopped further fetching here to respect shared rate limits.


## Notable candidates considered and rejected (or not catalogued)
- Nielsen 2014 "training errors review" as named in the brief: the training-errors systematic review is Nielsen et al. 2012 (IJSPT); catalogued that, plus Nielsen et al. 2014 JOSPT (weekly progression cohort), which is the 2014 Nielsen paper usually cited.
- Hulin et al. 2014 (spikes in acute workload in cricket fast bowlers) and other team-sport ACWR papers: not running; Gabbett 2016 plus the critiques (Impellizzeri 2020) cover the concept.
- Bell et al. 2023 deloading Delphi (strength/physique sports): deload evidence is from resistance training, not distance running; no running-specific deload trial identified, so 'deload weeks' remains an evidence gap (covered indirectly by Foster 1998 monotony, Aubry 2014, Bellinger 2020, Soligard 2016).
- Grandou et al. 2020 overtraining in resistance exercise review: strength-sport population, out of scope.
- Costa et al. 2019 ultramarathon nutrition and Tiller et al. 2019 ISSN ultramarathon position stand: ultra distances beyond the app's 5k-marathon scope.
- Toresdahl et al. (NYC Marathon training patterns and injury): could not be verified - WebSearch budget exhausted before the query ran.
- Not catalogued because they could not be verified before rate limits/budgets ran out (good candidates for a follow-up pass): Nieman et al. 1990 Los Angeles Marathon infection survey (PMID 2266764); Johnston et al. 2018 JSAMS training load and injury in endurance sports; van Poppel et al. 2021 JSHS risk factors short vs long-distance running; Kraus et al. 2019 BJSM Triad risk scores and BSI in male runners; Tenforde et al. 2013 MSSE sex-specific stress-fracture risk factors in adolescent runners; Schwellnus et al. 2019 SAFER VIII race medical screening; Hansen et al. 2014 IJSNEM and Atkinson et al. 2011 IJSM marathon in-race/pre-race carbohydrate field studies; Malta et al. 2021 cold-water immersion meta-analysis; Davis et al. 2020 sports massage meta-analysis; Le Meur et al. 2013 overreaching detection in triathletes; Carrard et al. 2022 OTS diagnosis scoping review; Sims et al. 2023 ISSN female athlete position stand; Pedlar et al. 2018 iron in female athletes.
- Gap note: a systematic sweep for 2023-2026 publications could not be run (WebSearch exhausted; OpenAlex discovery query rate-limited), so the newest items are Mountjoy 2023, Hoenig 2023 and Frandsen 2025. A follow-up pass should search 2023-2026 for running-injury cohorts/meta-analyses, sleep and recovery in endurance runners, and marathon in-race carbohydrate studies.
