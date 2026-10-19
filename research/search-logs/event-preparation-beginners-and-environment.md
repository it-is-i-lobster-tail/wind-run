# Search log: researcher G (event preparation and tapering; beginners and adherence; environment, heat and altitude)

## Engines and databases used
- WebSearch (standard mode), until the shared per-turn WebSearch budget was used up (by all parallel agents together).
- Europe PMC REST API through WebFetch: almost every call got HTTP 429 (rate limited, because the proxy is shared with the other researchers). Only 1 record was retrieved (Bosquet 2007).
- OpenAlex API (api.openalex.org) through WebFetch: used to verify metadata (DOI, PMID, PMCID through the PMC location, OA status and license, full author list) and to read abstracts reconstructed from abstract_inverted_index. Once WebSearch was exhausted, OpenAlex title/keyword search was also used for discovery. It is a bibliographic database of the same kind as Europe PMC, not a general web search engine.
- Semantic Scholar Graph API (api.semanticscholar.org): one record lookup (Hottenrott 2016; the abstract had been removed by the publisher).
- Publisher, repository and index pages read through WebFetch: journals.plos.org, frontiersin.org (PDF), bjsm.bmj.com, journals.sagepub.com, redalyc.org, repub.eur.nl / pure.eur.nl, experts.umn.edu, epublications.marquette.edu, lida.sport-iat.de / sponet.de (BISp records with abstracts), coachsci.sdsu.edu, ehu.eus, opus.lib.uts.edu.au, ideas.repec.org, marathonhandbook.com (only to get the author list and DOI of DeJong Lempke 2025).
- NCBI E-utilities was blocked by robots.txt. pubmed and PMC pages were not fetched (captcha). PMIDs and PMCIDs come from search-result URLs and OpenAlex records.

## Queries (one per line)
- WebSearch: Bosquet 2007 effects of tapering on performance meta-analysis Medicine Science Sports Exercise
- Europe PMC: EXT_ID:17762369 AND SRC:MED (core) -> OK
- Europe PMC: (TITLE:"tapering" OR TITLE:"taper") AND (ABSTRACT:"meta-analysis" OR ABSTRACT:"systematic review") -> 429
- Europe PMC: (TITLE:"tapering" OR TITLE:"taper") AND (TITLE:"meta-analysis" OR TITLE:"review") -> 429
- WebSearch: Wang 2023 "Effects of tapering on performance in endurance athletes" systematic review meta-analysis PLoS One
- WebSearch: Smyth Lawlor 2021 "Longer Disciplined Tapers Improve Marathon Performance for Recreational Runners" Frontiers
- Europe PMC: DOI:10.3389/fspor.2021.735220 OR DOI:10.1371/journal.pone.0282838 -> 429
- WebSearch: Mujika Padilla 2003 "Scientific bases for precompetition tapering strategies" Med Sci Sports Exerc
- WebSearch: Doherty Keogh Smyth Caulfield 2020 "training determinants of marathon performance" meta-analysis meta-regression J Sci Med Sport
- WebSearch: "Doherty C" "Keogh A" "Davenport J" "Lawlor A" "Smyth B" "Caulfield B" marathon
- Europe PMC: EXT_ID:31704026 OR EXT_ID:12840640 -> 429
- WebSearch: "Training for a (half-)marathon: Training volume and longest endurance run related to performance and running injuries" Scand J Med Sci Sports 30(9)
- WebSearch: "Training Volume and Training Frequency Changes Associated with Boston Marathon Race Performance"
- WebSearch: Boston Marathon 2022 registrants training frequency changes race performance Sports Medicine Tenforde OR Fredericson authors
- WebSearch: Tanda 2011 "Prediction of marathon performance time on the basis of training indices" Journal of Human Sport and Exercise
- WebSearch: Hagan Smith Gettman 1981 "Marathon performance in relation to maximal aerobic power and training indices"
- WebSearch: "Marathon performance in relation to maximal aerobic power and training indices" pubmed
- WebSearch: Billat Demarle Slawinski Paiva Koralsztein 2001 "Physical and training characteristics of top-class marathon runners"
- WebSearch: pubmed "top-class marathon runners" Billat Med Sci Sports Exerc 2001 33(12) 2089
- WebSearch: "10.1097/00005768-200112000-00018"
- Europe PMC: TITLE:"top-class marathon runners" OR TITLE:"marathon performance in relation to maximal aerobic power" -> fetch error; billat top-class marathon runners -> 429
- WebSearch: "An evaluation of the training determinants of marathon performance" Doherty researchrepository ucd
- WebSearch: jsams.org "training determinants of marathon performance" meta-regression 2020 Doherty Caulfield
- WebSearch: Smyth "How recreational marathon runners hit the wall" large-scale data analysis late-race pacing collapse PLoS One
- WebSearch: Smyth 2018 "Fast starters and slow finishers" pacing marathon recreational runners Journal of Sports Analytics
- WebSearch: Deaner Carter Joyner Hunter 2015 "Men are more likely than women to slow in the marathon"
- WebSearch: "PMC4289124"
- WebSearch: Ely Cheuvront Roberts Montain 2007 "Impact of weather on marathon-running performance"
- WebSearch: Ely Martin Cheuvront Montain 2008 "Effect of ambient temperature on marathon pacing is dependent on runner ability"
- WebSearch: El Helou 2012 "Impact of environmental parameters on marathon running performance" PLoS One
- WebSearch: Racinais 2015 "Consensus recommendations on training and competing in the heat" British Journal of Sports Medicine
- WebSearch: pubmed Racinais Consensus recommendations on training and competing in the heat Br J Sports Med 2015 49(18):1164
- WebSearch: "PMC4602249"
- Europe PMC: DOI:10.1136/bjsports-2015-094915 -> 429
- NCBI eutils esearch by DOI -> blocked by robots.txt
- OpenAlex: works/https://doi.org/10.1136/bjsports-2015-094915
- OpenAlex: works?filter=doi:<3 DOIs> (batch verification calls x3: Doherty/Tanda/Deaner; Ely 2008/Smyth 2018/Wang 2023; Smyth 2021 taper/DeJong Lempke/Smyth 2021 wall)
- OpenAlex search: Physical and training characteristics of top-class marathon runners
- OpenAlex search: Marathon performance in relation to maximal aerobic power and training indices
- OpenAlex: works/https://doi.org/10.2147/oajsm.s141657
- OpenAlex search: training and racing behavior of recreational runners by race distance NURMI
- OpenAlex: works/https://doi.org/10.3389/fpsyg.2023.1269374
- OpenAlex search: run walk strategy marathon recreational runners Hottenrott
- WebSearch: Hottenrott 2016 run/walk strategy marathon ... -> not run (shared WebSearch budget used up)
- OpenAlex search: run/walk strategy cardiovascular stress fatigue marathon
- Europe PMC: EXT_ID:25467199 -> 429; Semantic Scholar paper DOI:10.1016/j.jsams.2014.11.010 (abstract removed by publisher); doi.org -> 429
- OpenAlex search: reasons and predictors of discontinuation of running novice runners -> 429
- Semantic Scholar search: reasons and predictors of discontinuation of running novice runners -> fetch error
- OpenAlex search: discontinuation of running after a running program for novice runners (found Fokkema 2019 and the NLstart2run design paper)
- Europe PMC: EXT_ID:29934211 AND SRC:MED (core) -> OK (Fokkema 2019 abstract)
- OpenAlex search: Is running associated with a lower risk of all-cause cardiovascular and cancer mortality -> HTTP 403. The session web-fetch budget (400/hour, shared by all agents) was used up. Discovery stopped here, as the proxy message required ("do not retry in a loop: use what you have").

## Budget and rate-limit notes
- The WebSearch budget (200 per turn, shared by all agents) ran out after about 35 of my queries.
- Europe PMC returned HTTP 429 on 8 of 10 attempts. doi.org also returned 429 once.
- Then the WebFetch budget (400/hour, shared) ran out. So the catalog has 23 verified sources, short of the 40 target. The beginners-and-adherence and environment-heat-and-altitude topics are thin (see gaps below).

## Candidates seen but not catalogued (rejected or deferred)
- Kluitenberg B et al. 2013, NLstart2run study design (BMC Public Health 13:685): a protocol paper with no abstract in the record. Deferred; the results papers of the cohort would be better.
- Wirnitzer K et al. 2021, NURMI Step 1 diet groups (Nutrients 13(10):3521): about diet type (omnivore/vegetarian/vegan), not training. Rejected for this scope.
- Knechtle B et al. 2021, NURMI Step 1 training/racing behaviour by distance (Front Physiol 12:620404): verified, but its abstract is vague. Mentioned inside the NURMI Step 2 entry instead of catalogued separately.
- Takayama F et al. 2018/2019, single-runner marathon-season case studies (Taiikugaku Kenkyu; Int J Sport Health Sci): n=1 case studies. Rejected (low evidence level).
- Stellingwerff T 2012, case study of nutrition and training periodization in three elite marathoners (IJSNEM 22(5):392-400): metadata only, no abstract read. Better suited to the nutrition topic. Deferred.
- Norris M 2017, stride-time variability thesis; Kais U 2016, World Marathon Majors pacing thesis; Arne B 1999, personal marathon-training thesis: theses with no abstract, or anecdotal. Rejected.
- Grivas GV 2025, sub-2-hour marathon framework (Eur J Appl Physiol): elite and record-oriented, not relevant to recreational preparation. Rejected.

## Unverified leads for a follow-up pass (NOT catalogued; identifiers deliberately omitted until verified)
Priority candidates from my own knowledge of the literature. Each still needs an abstract or landing-page check:
- beginners-and-adherence: Pedisic et al. 2020 (BJSM; running and all-cause/CVD/cancer mortality meta-analysis); Lee DC et al. 2014 (JACC; leisure-time running and mortality); Hespanhol Junior et al. 2015 (Sports Med; meta-analyses of habitual running on health in inactive adults); Buist et al. 2008 (Am J Sports Med; graded training programme RCT in novice runners); Bredeweg et al. 2012 (BJSM; preconditioning programme RCT in novices); Kluitenberg et al. 2015 (Scand J Med Sci Sports; NLstart2run injury incidence); Videbaek et al. 2015 (Sports Med; injuries per 1000 h by runner type, including novices); Nielsen RO et al. (DANO-RUN novice cohort papers); Menheere et al. 2020 (IJERPH; reasons to quit running); Janssen et al. 2017 (PLoS One; who uses running apps and sports watches); Dallinga et al. 2018 (JMIR mHealth; features of effective sports apps); Pereira et al. 2021 (Front Psychol; systematic review of psychological correlates of recreational running); Grunseit et al. 2020 (Prev Med Rep; parkrun scoping review); Stevinson & Hickson 2014 (J Public Health; parkrun); Quirk et al. 2021 (BMC Public Health; parkrun participant survey); any peer-reviewed evaluation of the NHS Couch to 5K programme/app.
- environment-heat-and-altitude: Periard, Racinais & Sawka 2015 (Scand J Med Sci Sports; heat acclimation adaptations); Periard, Eijsvogels & Daanen 2021 (Physiol Rev; exercise under heat stress); Tyler et al. 2016 (Sports Med; heat adaptation meta-analysis); Daanen et al. 2018 (Sports Med; heat acclimation decay and re-induction meta-analysis); Roberts et al. 2021 (Curr Sports Med Rep; ACSM expert consensus on exertional heat illness); Racinais et al. 2022 (BJSM; Doha 2019 World Championships heat study); Mantzios et al. 2022 (MSSE; weather and endurance running performance across 1258 races); Knechtle et al. 2019 (PLoS One; weather and Boston Marathon 1972-2018); Vihma 2010 (Int J Biometeorol; weather and marathon performance); Bonetti & Hopkins 2009 (Sports Med; meta-analysis of sea-level performance after hypoxic adaptation); Levine & Stray-Gundersen 1997 (J Appl Physiol; live high-train low); Chapman et al. 1998 (J Appl Physiol; individual response to altitude training); Siebenmann et al. 2012 (J Appl Physiol; placebo-controlled LHTL with null result); Lundby & Robach 2016 (Exp Physiol; skeptical review); Mujika, Sharma & Stellingwerff 2019 (Sports Med; periodization of altitude training); Girard et al. 2020 (Front Sports Act Living; living low-training high panorama); Marr & Ely 2010 (MSSE; air pollution and marathon performance); Giles & Koehle 2014 (Sports Med; exercise in air pollution); Castellani & Tipton 2016 (Compr Physiol; cold stress and exercise) or the ACSM 2006 cold-injury position stand; Minetti et al. 2002 (J Appl Physiol; energy cost of uphill and downhill running) and Vernillo et al. 2017 (Sports Med; uphill/downhill running review), for grade-adjusted pace.
- event-preparation-and-tapering: Spilsbury et al. 2019 (Eur J Sport Sci; tapering in elite British endurance runners); Houmard et al. 1994 (MSSE; taper in distance runners); Mujika 2010 (Scand J Med Sci Sports; intense training before and during the taper); Casado et al. 2022 (IJSPP; systematic review of training of highly trained distance runners); Casado et al. 2021 (JSCR; world-class performances predicted by easy-run volume and deliberate practice of intervals and tempo runs); Haugen et al. 2022 (Sports Med Open; training of world-class distance runners); Bradbury et al. 2020 (JSCR; linear vs reverse-linear periodisation in runners); Gunnarsson & Bangsbo 2012 (J Appl Physiol; 10-20-30 training and 5 km performance in recreational runners); Munoz et al. 2014 (IJSPP; polarised training and 10 km performance in recreational runners); Vickers & Vertosick 2016 (BMC Sports Sci Med Rehabil; race times and training in recreational runners); Damsted et al. 2019 (JOSPT; ProjectRun21, weekly distance change and injury in half-marathon preparation); Buman et al. 2008 (Psychol Sport Exerc; hitting the wall phenomenology); Santos-Lozano et al. 2014 (IJSM; marathon pacing by sex and level); Diaz et al. 2018 (Eur J Sport Sci; pacing in marathon world records).
