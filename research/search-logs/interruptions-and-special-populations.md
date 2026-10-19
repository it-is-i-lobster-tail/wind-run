# Search log: researcher B (interruptions-detraining-and-return; special-populations)

## Engines/databases used
- WebSearch (standard mode) for discovery and PubMed/PMC/publisher URLs
- Europe PMC REST API (search, resultType core/lite) for metadata and abstracts (heavily rate-limited by the proxy during this session, HTTP 429 on many calls)
- OpenAlex API (works/pmid:, works?filter=pmid:/doi:) for metadata, ids, OA status and abstract reconstruction (also intermittently rate-limited)
- Publisher / repository landing pages via WebFetch (bjsm.bmj.com, bmjopensem.bmj.com, link.springer.com, mdpi.com, frontiersin.org, doaj.org, sponet.de, repository.up.ac.za, search.pedro.org.au, cochranelibrary.com, coachsci.sdsu.edu, ehu.eus)

## Queries run (one per line)
- WebSearch: Mujika Padilla detraining loss of training-induced physiological and performance adaptations Part I short term insufficient training stimulus
- Europe PMC: (TITLE:"detraining" AND AUTH:"Mujika") -> HTTP 429 (not read)
- Europe PMC: EXT_ID:10966148 AND SRC:MED
- Europe PMC: (TITLE:"detraining" AND TITLE:"Part II" AND AUTH:"Mujika") -> HTTP 429 (not read)
- WebSearch: Mujika Padilla 2000 "Detraining" "Part II" long term insufficient training stimulus Sports Medicine 30(3) 145-154
- WebSearch: Coyle 1984 "Time course of loss of adaptations after stopping prolonged intense endurance training" J Appl Physiol
- WebSearch: Hickson "Reduced training intensities and loss of aerobic power, endurance, and cardiac growth" 1985
- WebSearch: Hickson Rosenkoetter "Reduced training frequencies and maintenance of increased aerobic power" 1981
- Europe PMC: AUTH:"Hickson RC" AND TITLE:"reduced training"
- Europe PMC: AUTH:"Coyle EF" AND (TITLE:"detraining" OR TITLE:"stopping")
- Europe PMC: AUTH:"Houmard JA" AND (TITLE:"training cessation" OR ...) -> fetch error
- WebSearch: Houmard "Effect of short-term training cessation on performance measures in distance runners" Int J Sports Med 1992
- Europe PMC: EXT_ID:1487339 -> HTTP 429; DOI:10.1055/s-2007-1024567 -> HTTP 429
- WebSearch: Spiering Mujika 2021 "Maintaining Physical Performance: The Minimal Dose of Exercise Needed..."
- WebSearch: Houmard 1990 "Reduced training maintains performance in distance runners"
- WebSearch: Mujika Padilla 2001 "Cardiorespiratory and metabolic characteristics of detraining in humans"
- WebSearch: Neufer 1989 "The effect of detraining and reduced training on the physiological adaptations to aerobic exercise training"
- Europe PMC: DOI:10.3389/fphys.2023.1334766
- WebSearch: Houmard 1992 training cessation distance runners 14 days VO2max time to exhaustion citrate synthase abstract
- WebSearch: McConell 1993 "Reduced training volume and intensity maintain aerobic capacity but not performance in distance runners"
- OpenAlex: works/pmid:33629972; works?filter=pmid:8440543|11252068|1487339|10966148
- OpenAlex: works?filter=doi:10.2165/00007256-200030030-00001|10.1136/bjsports-2020-102637|10.1136/bjsports-2022-105759
- WebSearch: International Olympic Committee consensus statement on acute respiratory illness in athletes part 1 ... return to sport
- WebSearch: Weidner 1998 "The effect of exercise training on the severity and duration of a viral upper respiratory illness"
- WebSearch: Elliott 2020 graduated return to play guidance following COVID-19 infection BJSM infographic
- WebSearch: return to running after injury programme progression scoping review criteria walk-run
- WebSearch: Warden Davis Fredericson 2014 management and prevention of bone stress injuries in long-distance runners JOSPT return to running
- WebSearch: van Tonder Schwellnus 2016 cohort 7031 distance runners systemic symptoms acute illness before race not finishing BJSM
- OpenAlex: works?filter=doi:10.1007/s40279-024-02051-y
- OpenAlex search / Crossref query for SAFER IV -> HTTP 429 (not read)
- WebSearch: Goom Donnelly Brockwell 2019 returning to running postnatal guidelines
- WebSearch: Christopher Donnelly Brockwell Delphi consensus return-to-running readiness after childbirth BJSM
- WebSearch: ACOG Committee Opinion 804 Physical Activity and Exercise During Pregnancy and the Postpartum Period
- WebSearch: Kuhrt 2018 recreational running pregnancy earlier delivery lower birth weight 1293 female runners
- WebSearch: Bo IOC expert group meeting exercise and pregnancy in recreational and elite athletes 2016 evidence summary part 1 BJSM
- WebSearch: Krabak 2021 youth running consensus statement minimising risk of injury and illness in youth runners BJSM
- WebSearch: Tanaka Seals 2008 endurance exercise performance in Masters athletes ...
- WebSearch: McNulty 2020 effects of menstrual cycle phase on exercise performance in eumenorrheic women systematic review meta-analysis
- WebSearch: Bruinvels 2021 prevalence and frequency of menstrual cycle symptoms availability to train compete 6812 exercising women Strava BJSM
- WebSearch: "The Impact of Training on the Loss of Cardiorespiratory Fitness in Aging Masters Endurance Athletes"
- WebSearch: retraining after detraining endurance athletes VO2max recovery time regain fitness after training break study
- WebSearch: frontiersin fphys.2024.1508642 detraining retraining
- WebSearch: Raysmith Drew 2016 performance success or failure influenced by weeks lost to injury and illness elite Australian track and field athletes
- Europe PMC: TITLE:"weeks lost to injury and illness" -> HTTP 429 (not read)
- WebSearch: Janse van Rensburg 2021 managing travel fatigue and jet lag in athletes a review and consensus statement
- WebSearch: Schwellnus 2012 elite athletes travelling international destinations >5 time zone differences illness BJSM
- WebSearch: Reilly Waterhouse 2007 coping with jet-lag position statement European College of Sport Science
- WebSearch: pubmed Raysmith BP Drew MK "Performance success or failure is influenced by weeks lost..."
- WebSearch: pubmed Weidner Cranston Schurr Kaminsky 1998 Med Sci Sports Exerc rhinovirus exercise training severity duration
- WebSearch: "The effect of exercise training on the severity and duration of a viral upper respiratory illness" Med Sci Sports Exerc 30(11)
- WebFetch (PEDro): record-detail/9862 -> identified Weidner & Schurr 2003 BJSM
- WebFetch (Cochrane): CD010596.pub3 references page (exercise vs no exercise for acute respiratory infections)
- OpenAlex: works?filter=title.search:youth running consensus statement
- WebFetch: experts.colorado.edu Tanaka & Seals 2008 record
- WebSearch: Hollander 2021 sex-specific running injuries / Besson 2022 sex differences endurance running / Nielsen 2014 obese novice runners -> NOT RUN (shared WebSearch budget of 200 calls/turn exhausted)
- OpenAlex: works?filter=doi:10.1113/jphysiol.2007.141879|10.1007/s40279-020-01319-3 (DOIs recalled, verified by API)
- OpenAlex: works?filter=doi:10.1136/bjsports-2020-102792|10.1007/s40279-020-01412-7
- OpenAlex: works?filter=doi:10.1007/s40279-020-01317-5|10.1007/s40279-022-01706-y -> HTTP 403 (shared WebFetch budget of 400/hour exhausted; not read)
- WebFetch: Goom/Donnelly/Brockwell 2019 postnatal guideline PDF (athleticsni.org)
- WebFetch: opqic.org ACOG Committee Opinion 804 abstract page
- WebFetch: bjsm.bmj.com/content/50/10/571 (Bo 2016 IOC pregnancy part 1) -> HTTP 403 budget exhausted (not read)
- OpenAlex: works?filter=doi:10.1007/s40279-022-01706-y|10.1136/bjsports-2020-102025 (Craven 2022 sleep-loss MA; Walsh 2021 sleep consensus) -> HTTP 403 budget exhausted (not read)
- OpenAlex: works?filter=doi:10.3389/fphys.2012.00051|10.1007/s40279-016-0578-x (Ruuska 2012 mental stress & training response; Ivarsson 2017 psychosocial injury MA) -> HTTP 403 budget exhausted (not read)
- Stopped fetching after repeated "web-fetch budget exhausted" responses, as instructed by the proxy.

## Access problems encountered
- Europe PMC REST API returned HTTP 429 (rate limited) on roughly half of calls; pages refused once were not re-fetched.
- Shared WebSearch budget (200 calls/turn across all researchers) ran out mid-session.
- Shared WebFetch budget (400/hour across all agents) ran out near the end; remaining candidates below could not be verified.
- thieme-connect.com / .de (Int J Sports Med) served a bot-check page; abstracts obtained via OpenAlex/sponet instead.
- journals.physiology.org, link.springer.com (one Sports Med 2000 article), figshare and Semantic Scholar API returned fetch errors.

## Candidates rejected or not catalogued (and why)
- Neufer 1989 Sports Med "The effect of detraining and reduced training..." - search surfaced only a journal-issue listing; record/abstract not verified.
- Sinacore 1993 Phys Ther; Chi 1983 Am J Physiol; Martin 1984 J Appl Physiol (Coyle group detraining papers) - mechanistic (fibre enzymes, lipolysis, torque recovery), little practical value beyond Coyle 1984/1985/1986.
- Hickson, Overland & Dougherty 1984 (reduced training frequency in rats) - animal study.
- Scheer et al. 2021 Sports Med "Recommendations on Youth Participation in Ultra-Endurance Running Events" (seen in OpenAlex) - ultra distances outside 5k-marathon scope.
- Grande et al. Cochrane CD010596.pub3 "Exercise versus no exercise for the occurrence, severity, and duration of acute respiratory infections" - results page read, but author list could not be confirmed before budget ran out and it addresses regular exercise/prevention rather than running while ill; good follow-up candidate.
- Bo et al. 2016 IOC "Exercise and pregnancy in recreational and elite athletes" part 1 (BJSM 50(10):571) - landing page not read (budget); strong follow-up candidate.
- Donnelly et al. 2020 BJSM infographic on returning to running postnatally (Canterbury repository) - seen in search results only.
- Drew, Raysmith & Charlton 2017 BJSM systematic review "Injuries impair the chance of successful performance by sportspeople" and Canberra "Sport performance success or failure depends on degree of modified training" - seen in search results only.
- Warden, Davis & Fredericson 2014 JOSPT (bone stress injury management) - record not surfaced; return-to-run content covered by George et al. 2024 scoping review.
- AUT scoping review "The return to run process for females following a tibial bone stress injury" - seen in search results only.
- sponet record "Endurance exercise performance in masters runners: physiological determinants and training recommendations" - seen only, not read.
- Lollgen BJSM 2020 COVID return-to-play infographic (worldrowing PDF copy) - not read; Elliott et al. 2020 used instead.
- Popular articles (runnersconnect.net, trainingpeaks.com, outsideonline.com, realbuzz, road.cc, trainright.com) - not peer-reviewed; used only as pointers.
- ICS 2024 conference abstract on postpartum return-to-run strategies - conference abstract only.
- Third-party PDF copies of paywalled papers (paulogentil.com, runpanel.co.il, njsiaa.org) - not used as pdf_url.

## Known gaps (planned but not verified because budgets ran out)
- Life/psychological stress and adaptation/injury: Ruuska et al. 2012 Front Physiol; Ivarsson et al. 2017 Sports Med MA; Stults-Kolehmainen & Sinha 2014 Sports Med; Bartholomew et al. 2008 JSCR.
- Sleep deprivation: Craven et al. 2022 Sports Med MA; Walsh et al. 2021 BJSM consensus; Fullagar et al. 2015 Sports Med.
- Post-COVID cardiac return-to-play: Wilson et al. 2020 BJSM; Kim et al. 2021 JAMA Cardiol; Salman et al. 2021 BMJ.
- Coaching-manual break rules (e.g., Daniels' Running Formula VDOT adjustments after time off); hospital/physio walk-run return-to-run programmes.
- Masters injury and recovery: McKean et al. 2006 Clin J Sport Med; Borges et al. 2016 J Aging Phys Act; Fell & Williams 2008.
- Overweight/obese novices: Nielsen et al. 2014 Int J Sports Phys Ther; Buist et al. 2010 Am J Sports Med; Nielsen et al. 2013 (930 novices).
- Youth: AAP (Brenner) overuse/specialisation statements.
- Female: Elliott-Sale et al. 2020 oral-contraceptive MA; Besson et al. 2022 sex differences in endurance running.
- Pregnancy: Mottola et al. 2018 Canadian guideline; Bo et al. 2016-2018 IOC series.
- Chronic conditions: Riddell et al. 2017 type 1 diabetes exercise consensus.
- Tapering-style reduced training: Bosquet et al. 2007 MSSE taper meta-analysis (likely covered by the tapering reviewer).
