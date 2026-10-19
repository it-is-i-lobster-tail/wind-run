# Search log - scope I (organization-guides-and-templates)

## Queries run (WebSearch, standard mode unless noted)
- NHS Couch to 5K week by week plan
- NHS website content Open Government Licence terms reuse nhs.uk
- nhs.uk "content not covered" open government licence syndication
- nhs.uk running tips for beginners how to avoid injury running
- parkrun official guidance beginners walking running 5k training plan blog
- parkrun.com couch to 5k parkrun health wellbeing "walk" participants guidance (allowed_domains parkrun.com / blog.parkrun.com / parkrun.org.uk)
- England Athletics RunTogether beginner running programme "Couch to 5k" guide
- England Athletics "Coach in Running Fitness" course content qualification
- England Athletics "Leadership in Running Fitness" LiRF course content (allowed_domains englandathletics.org)
- Athletics Ireland Fit4Life beginners running programme couch to 5k plan
- HSE Get Ireland Active couch to 5k plan running beginners
- TCS London Marathon official training plans beginner improver marathon training plan
- NYRR New York Road Runners free marathon training plan beginner intermediate PDF
- nyrr.org training plans marathon "training plan" runners (allowed_domains nyrr.org)
- webassets.nyrr.org training-guides marathon moderate aggressive training plan pdf
- "nyrr" marathon training plan "moderate" OR "ambitious" 18 weeks pdf webassets (allowed_domains nyrr.org)
- Boston Athletic Association B.A.A. training plans marathon level 1 level 2 level 3 level 4
- Chicago Area Runners Association CARA marathon training program 18 weeks training plan
- cararuns.org marathon training program training schedule (allowed_domains cararuns.org)
- BMW BERLIN-MARATHON official training plan Trainingsplan
- RRCA Road Runners Club of America coaching certification program curriculum course content
- USATF coaching education Level 1 course curriculum endurance Level 2 endurance school
- IAAF "Introduction to Coaching Theory" Peter Thompson CECS Level I pdf
- World Athletics Coaches Education and Certification System CECS level 1 level 2 endurance coaching academy
- IAAF CECS Level II "middle and long distance" coaching manual pdf endurance training planning
- Athletics Canada Long-Term Athlete Development LTAD 2.0 endurance running pdf
- athletics.ca long term athlete development framework "Athletics Canada" LTAD document (allowed_domains athletics.ca)

## Rejected / not catalogued (and why)
- parkrun blog pages (blog.parkrun.com "Couch-to-5k and parkrun support each other", "Nine ways to start with parkrun", "Walking at parkrun") and parkrun.org.uk event news: every fetch failed (site blocks the fetcher), so they could not be initially read. parkrun also publishes no training plan of its own.
- Local council / NHS-trust / club Couch to 5K copies (healthwell.eani.org.uk, bwellbelfast.hscni.net, clubspark.englandathletics.org club pages, council PDFs): derivative copies of the NHS plan, not primary organisation documents.
- Athletics Ireland Fit4Life pages and HSE "Get Ireland Active": search returned only club/regional news items, no national plan document.
- NYRR runner-resources hub and NYRR stories pages: robots.txt disallows fetching; only the conservative plan PDF on webassets.nyrr.org could be read. NYRR now pushes a commercial partner app (Runna) for other plans.
- NYRR moderate/aggressive plan PDFs: not found by search.
- CARA detailed schedules: the plans are only given to registered members; the public programme pages were catalogued instead.
- CARA Beginner 5K page (cararuns.org/beginner5k): fetched, but it has no plan content (just schedule of meet-ups and a coach contact), so it was not catalogued separately.
- World Athletics "Run! Jump! Throw!" (IAAF kids' athletics guide): children's multi-event teaching guide, not distance-running training.
- Commercial plans surfaced by searches (Runna, Coopah, TrainingPeaks, Marathon Handbook, run247, active.com, findyouredge.app): commercial/non-authoritative, out of scope.
- World Athletics Level I and Level III CECS PDFs: same system description as the Level II PDF already linked from the CECS entry; not separately catalogued.

## Budget / access problems encountered
- WebSearch: the shared per-turn search budget (200 calls shared by all parallel agents) was exhausted after ~25 of my queries; the query '"Quantity and Quality of Exercise for Developing and Maintaining Cardiorespiratory, Musculoskeletal, and Neuromotor Fitness" journals.lww.com acsm-msse fulltext' was refused. No further searches were possible.
- WebFetch: https://doi.org/10.1249/MSS.0b013e318213fefb and a Europe PMC title query (TITLE:"guidelines on physical activity and sedentary behaviour") were refused by the proxy with HTTP 429 (rate limited); then the shared WebFetch budget (400/hour across all agents) was reported exhausted when fetching https://www.halhigdon.com/training/marathon-training/novice-1-marathon/.
- Consequence: items below that needed new URLs (WHO 2020, US PAG 2018, UK CMO 2019, Hal Higdon, Galloway, Daniels, Pfitzinger, Hansons, Lydiard, ACSM brochures, AAOS, postnatal return-to-running) could only be catalogued if a later fetch succeeded.

## Direct fetches made after the search budget ran out (URLs of well-known official pages)
- https://www.who.int/publications/i/item/9789240015128 (OK) -> PDF link on IRIS returned a fetch error (target error), so WHO detailed figures not read
- https://odphp.health.gov/our-work/nutrition-physical-activity/physical-activity-guidelines/current-guidelines (OK) + executive summary PDF (OK)
- https://www.gov.uk/government/publications/physical-activity-guidelines-uk-chief-medical-officers-report (OK); main HTML report refused (fetch budget exhausted again)
- https://www.halhigdon.com/training/marathon-training/novice-1-marathon/ -> target error (wrong path); https://www.halhigdon.com/training-programs/marathon-training/novice-1-marathon/ (OK)
- https://www.jeffgalloway.com/training/run-walk-run-method/ -> target error (wrong path); https://www.jeffgalloway.com/ (OK) -> https://www.jeffgalloway.com/training/run-walk/ (OK); Magic Mile page refused (fetch budget exhausted)
- https://www.mayoclinic.org/healthy-lifestyle/fitness/in-depth/5k-run/art-20050962 (OK)
- https://us.humankinetics.com/products/daniels-running-formula-4th-edition (OK)
- https://us.humankinetics.com/products/advanced-marathoning-3rd-edition (OK; page now shows the 4th edition, (c)2026)
- https://www.lydiardfoundation.org/ (OK) -> https://www.lydiardfoundation.org/free-starter-plans (OK)
- https://www.athleticsireland.ie/living-the-fit-life/ (OK; URL from earlier search results)
- https://www.halhigdon.com/training-programs/half-marathon-training/novice-1-half-marathon/ (OK)
- https://csepguidelines.ca/guidelines/adults-18-64/ (OK)
- https://www.health.gov.au/topics/physical-activity-and-exercise/physical-activity-and-exercise-guidelines-for-all-australians/for-adults-18-to-64-years (OK)
- https://www.acsm.org/education-resources/books/guidelines-exercise-testing-prescription -> refused (fetch budget exhausted)
- https://www.acsm.org/education-resources/books/guidelines-exercise-testing-prescription (OK on second attempt; first was a budget refusal, not a page error)
- https://absolute.physio/wp-content/uploads/2019/09/returning-to-running-postnatal-guidelines.pdf (OK)
- https://www.nhs.uk/conditions/sports-injuries/ -> refused (fetch budget exhausted); stopped fetching here as instructed by the proxy message.

## Gaps not filled (no successful read in this pass)
- Hansons Marathon Method (book/official site): no URL available without search.
- ACSM running brochures (e.g., "Selecting and effectively using running shoes"): URL not confirmable without search.
- AAOS OrthoInfo / AMSSM runner-injury pages, NHS "Sports injuries": not read (budget).
- American Academy of Pediatrics youth-running guidance: not found (no search budget).
- Sports-medicine / hospital "return to running" protocols (e.g., post-injury run-walk progressions): not found (no search budget). Only the postnatal return-to-running guideline was read.
- USATF Coaching Manual (Human Kinetics book), Sport England, Athletics Australia, Health Canada running programmes, parkrun guidance (site blocked fetching): not catalogued.
- Galloway Magic Mile page (ratio/pace table) and UK CMO main HTML report: refused by fetch budget; WHO guideline PDF returned a target fetch error.
- Note: the WHO 2020 and UK CMO 2019 entries were catalogued from their official landing pages; headline figures in their summaries are flagged for confirmation in the full-text analysis.
