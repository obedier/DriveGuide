# wAIpoint Gold-Standard Tours — Calibration Set

**Purpose.** This is the calibration set for the tour scoring engine. Ten elite, hand-picked tours across the product's core archetypes, each designed to score `tour_absolute ≥ 85` under the starting weights in [tour-scoring-spec.md](./tour-scoring-spec.md). These are the quality bar — every AI-generated tour for the same city and intent is measured against the corresponding gold tour.

**What "gold-standard" means.**

1. **Calibration exemplars.** The scoring weights are tuned so these tours score high. If a gold tour scores 82, we retune the weights — not the tour.
2. **Training data.** Curators and the generator study these for signature-moment structure, stop sequencing, and pacing.
3. **Free-hook showcases.** Several of these ship as free benchmark tours in the app ("Best First Tour in NYC", "Romantic Sunset Paris"). They are the product's public standard.
4. **Not comprehensive.** Ten tours cover ten archetypes — not every city, not every intent. Coverage deepens as the scoring loop matures.

**Archetype coverage.**

| # | Archetype | Tour | City |
|---|---|---|---|
| 1 | Iconic driving | Mulholland to the Pacific | Los Angeles |
| 2 | Iconic walking | Centro Storico Classics | Rome |
| 3 | Scenic sunset drive | Golden Hour Bay Loop | San Francisco |
| 4 | Architecture-focused | River Architecture + Loop | Chicago |
| 5 | Food + neighborhood texture | Condesa-Roma Taco Crawl | Mexico City |
| 6 | First-time greatest-hits | Manhattan Classics | New York City |
| 7 | Romantic evening | Right Bank After Dark | Paris |
| 8 | Family-friendly | National Mall for Kids | Washington DC |
| 9 | Local flavor / hidden-gems-lite | Shimokitazawa Drift | Tokyo |
| 10 | 2-hour ultra-efficient | Causeway Miami | Miami |

---

## Per-tour schema

Each gold tour has:

- **Title, city, archetype, target duration, target user/use case**
- **Route logic** — 2-3 sentences on *why* this shape
- **Stop sequence** — each stop with structured attributes (stop_type, scores, cluster_id, best_time_of_day, etc.) per the schema in [tour-scoring-spec.md §6](./tour-scoring-spec.md#6-persisted-json-schema)
- **Signature moments** — the 3-5 emotional peaks
- **User-facing quality description** — the one sentence we'd show in the app
- **Benchmark score breakdown** — Layer A (7 dims + composite), Layer B intent_fit, final blended score

Score legend: 0-10 per dimension; composite 0-100. Formula in [tour-scoring-spec.md §3](./tour-scoring-spec.md#3-tour-level-scoring--layer-a-absolute-quality).

---

## Tour 1 — "Mulholland to the Pacific"

**City:** Los Angeles
**Archetype:** Iconic driving
**Target duration:** 2 hours
**Target user:** Visitor who wants the canonical LA drive — hills → Sunset Strip → Pacific. First-timers; also works for locals showing someone off.
**Start:** Griffith Observatory · **End:** Venice Boardwalk
**Intent tags:** `first_time_highlights`, `scenic_sunset`, `minimal_walking` (soft)

**Route logic.** LA is a car city and its signature journey is the descent from the hills to the ocean. Starting at Griffith guarantees a skyline-and-sign opener; Mulholland delivers the hilltop crescendo; Sunset Strip → Beverly Hills → PCH → Santa Monica at golden hour is the canonical emotional arc. Ending at Venice avoids the return-trip tax and gives the sunset finale every LA driving tour should have.

### Stop sequence

| # | Name | stop_type | iconicity | scenic | story | dwell (min) | friction | best_time | cluster |
|---|---|---|---|---|---|---|---|---|---|
| 1 | Griffith Observatory | viewpoint | 9 | 10 | 8 | 25 | medium | afternoon | la_hills |
| 2 | Mulholland Scenic Overlook (Laurel Cyn) | viewpoint | 7 | 9 | 6 | 10 | medium | afternoon | la_hills |
| 3 | Sunset Strip (Whisky, Chateau Marmont drive-by) | neighborhood | 8 | 6 | 9 | 10 | medium | afternoon | la_central |
| 4 | Rodeo Drive (Beverly Hills loop) | neighborhood | 8 | 6 | 6 | 10 | low | any | la_central |
| 5 | Sunset Blvd → Bel Air curves → Palisades | scenic_drive | 6 | 9 | 5 | 15 | low | afternoon | la_westside |
| 6 | Santa Monica Pier | icon | 9 | 9 | 7 | 20 | high | golden_hour | la_coast |
| 7 | Venice Boardwalk | neighborhood | 8 | 7 | 7 | 20 | medium | golden_hour | la_coast |

**Signature moments.**

- **Opening wow:** The skyline + Hollywood Sign framing from Griffith's west lawn.
- **Mid-tour crescendo:** The Laurel Canyon ridge reveal of the Westside basin.
- **Ending:** Santa Monica Pier ferris wheel lighting up as the sun drops over the Pacific.
- **Bonus:** Chateau Marmont drive-by — cheap, iconic, 10 seconds.

**User-facing description.** "The defining LA drive — hills, Sunset Strip, and golden hour at the Pacific."

### Benchmark score breakdown

**Layer A (absolute):**

| Dimension | Score | Notes |
|---|---|---|
| Iconic value | 9.0 | Griffith + Sunset + Rodeo + Santa Monica = stacked icons |
| Geographic coherence | 9.5 | One-way descending route, zero backtrack |
| Time realism | 8.5 | Tight at 2h with traffic; realistic 2h10-2h30 |
| Narrative flow | 9.5 | Clean setup → ridge crescendo → coast finale |
| Scenic payoff | 9.0 | Four hero views (skyline, ridge, Bel Air descent, pier) |
| Variety balance | 8.5 | Viewpoint + neighborhood + scenic_drive + icon mix |
| Practical usability | 8.0 | Parking at Griffith + Santa Monica is the only friction |

**`tour_absolute` composite: 90.0**

**Layer B intent fits:**

| Intent | Composite | Notes |
|---|---|---|
| first_time_highlights | 94 | Hits the canonical top-5 LA stops in order |
| scenic_sunset | 93 | Route is literally timed for golden hour at the coast |
| minimal_walking | 86 | Pier + Boardwalk add some walking; not strict-minimal |

**Final blend (pure_curation):** **90.0**
**Final blend (hybrid_default, scenic_sunset intent):** `0.6 × 90 + 0.4 × 93` = **91.2**

---

## Tour 2 — "Centro Storico Classics"

**City:** Rome
**Archetype:** Iconic walking
**Target duration:** 4 hours
**Target user:** First-time Rome visitor who wants to experience the ancient core + Renaissance piazzas on foot. Works for couples, solo, mixed groups.
**Start:** Colosseum · **End:** Piazza Santa Maria in Trastevere
**Intent tags:** `first_time_highlights`, `architecture_historic`, `photo_heavy`

**Route logic.** Rome's centro storico is one of the world's most walkable dense-icon zones. The route moves chronologically — ancient (Colosseum, Forum), Renaissance (Pantheon, Piazza Navona), then Tiber-side Baroque (Campo de' Fiori, Trastevere). South-to-north in the morning keeps sun at your back; afternoon crossing to Trastevere positions for an aperitivo finish.

### Stop sequence

| # | Name | stop_type | iconicity | scenic | story | dwell (min) | friction | best_time | cluster |
|---|---|---|---|---|---|---|---|---|---|
| 1 | Colosseum + Arch of Constantine | icon | 10 | 9 | 10 | 40 | low | morning | rome_ancient |
| 2 | Roman Forum + Palatine Hill | icon | 10 | 8 | 10 | 50 | low | morning | rome_ancient |
| 3 | Via dei Fori Imperiali → Piazza Venezia | scenic_drive | 7 | 7 | 8 | 10 | low | any | rome_central |
| 4 | Altar of the Fatherland terrace | viewpoint | 7 | 8 | 7 | 15 | low | any | rome_central |
| 5 | Trevi Fountain | icon | 10 | 9 | 8 | 20 | low | midday | rome_baroque |
| 6 | Sant'Eustachio / Giolitti — coffee or gelato | food | 6 | 4 | 7 | 15 | low | any | rome_baroque |
| 7 | Pantheon | icon | 10 | 9 | 10 | 20 | low | midday | rome_baroque |
| 8 | Piazza Navona (Bernini fountain) | icon | 9 | 8 | 9 | 15 | low | any | rome_baroque |
| 9 | Campo de' Fiori market | neighborhood | 7 | 6 | 7 | 15 | low | morning | rome_baroque |
| 10 | Ditirambo or Emma Pizzeria — lunch | food | 6 | 5 | 6 | 45 | low | midday | rome_baroque |
| 11 | Ponte Sisto → Trastevere entry | scenic_drive | 6 | 8 | 6 | 5 | low | afternoon | rome_trastevere |
| 12 | Piazza Santa Maria in Trastevere — aperitivo | neighborhood | 8 | 7 | 9 | 30 | low | afternoon | rome_trastevere |

**Signature moments.**

- **Opening wow:** Stepping into the Colosseum. No ramp-up needed.
- **Mid-tour awe:** The Pantheon oculus — nobody is prepared for it the first time.
- **Food crescendo:** Sant'Eustachio espresso or Giolitti gelato — the short pause that makes the whole walk feel earned.
- **Ending:** Aperol spritz in Piazza Santa Maria, golden light on the basilica.

**User-facing description.** "Rome's 2,000-year walk — ancient forum, Pantheon's oculus, and an aperitivo finish in Trastevere."

### Benchmark score breakdown

**Layer A:**

| Dimension | Score | Notes |
|---|---|---|
| Iconic value | 10 | Colosseum + Pantheon + Trevi + Navona — four global top-tier stops |
| Geographic coherence | 9.5 | Tight west-northwest arc; Trastevere crossing is natural, not a detour |
| Time realism | 8.5 | 4h with dwells; Forum can run long; buffer built in |
| Narrative flow | 9.5 | Chronological arc (ancient → Baroque → local finish) |
| Scenic payoff | 9.0 | Architecture-heavy; Tiber crossing + Pantheon oculus are visual peaks |
| Variety balance | 9.0 | Icon + viewpoint + food + neighborhood |
| Practical usability | 8.5 | ZTL keeps it walking-friendly; low parking/weather risk |

**`tour_absolute` composite: 93.0**

**Layer B intent fits:**

| Intent | Composite | Notes |
|---|---|---|
| first_time_highlights | 97 | Canonical top-5 Rome stops all included |
| architecture_historic | 95 | Pantheon, Colosseum, Baroque piazzas — period coherence perfect |
| photo_heavy | 92 | Pantheon interior, Trevi, Navona fountains — all photo-tier |

**Final blend (pure_curation):** **93.0**
**Final blend (hybrid_default, first_time intent):** `0.6 × 93 + 0.4 × 97` = **94.6**

---

## Tour 3 — "Golden Hour Bay Loop"

**City:** San Francisco
**Archetype:** Scenic sunset drive
**Target duration:** 2 hours
**Target user:** Visitor or local on a date or with a camera. Peak-SF single experience.
**Start:** Ferry Building · **End:** Baker Beach (sunset)
**Intent tags:** `scenic_sunset`, `romantic`, `photo_heavy`

**Route logic.** SF's hero bridge has two sides, and the north side at golden hour is the canonical photo. Start at Ferry Building (skyline baseline), run the Embarcadero north, climb the city on Lombard, cross the Golden Gate northbound, deliver the Battery Spencer hero shot, cross back south, and land at Baker Beach as the sun hits the towers. The full arc is emotional; there's no redundancy; the payoff is the finale.

### Stop sequence

| # | Name | stop_type | iconicity | scenic | story | dwell (min) | friction | best_time | cluster |
|---|---|---|---|---|---|---|---|---|---|
| 1 | Ferry Building + Embarcadero | waterfront | 8 | 7 | 8 | 10 | low | afternoon | sf_east |
| 2 | Coit Tower / Telegraph Hill drive-up | viewpoint | 8 | 9 | 8 | 15 | medium | afternoon | sf_east |
| 3 | Lombard Street (crooked section) | icon | 9 | 7 | 7 | 5 | medium | any | sf_central |
| 4 | Golden Gate Bridge — northbound crossing | icon | 10 | 10 | 9 | 5 | low | golden_hour | sf_bridge |
| 5 | Battery Spencer (Marin Headlands) | viewpoint | 10 | 10 | 8 | 20 | medium | golden_hour | sf_marin |
| 6 | GGB southbound return | scenic_drive | 9 | 10 | 8 | 5 | low | golden_hour | sf_bridge |
| 7 | Baker Beach | viewpoint | 9 | 10 | 7 | 20 | medium | golden_hour | sf_presidio |

**Signature moments.**

- **Opening:** The skyline from Pier 7 as you leave the Ferry Building.
- **Setup crescendo:** The eight hairpins of Lombard.
- **Primary payoff:** Battery Spencer — the canonical Golden Gate photo at golden hour.
- **Ending:** Baker Beach — the bridge framed by cypress, sun dropping, the only beach-level southside hero angle.

**User-facing description.** "Two golden-hour sides of the Golden Gate — Battery Spencer on the way out, Baker Beach on the way home."

### Benchmark score breakdown

**Layer A:**

| Dimension | Score | Notes |
|---|---|---|
| Iconic value | 9.5 | GGB counted twice (photo from each side) + Lombard + Ferry Building |
| Geographic coherence | 9.0 | Clean loop with one bridge reversal — but the reversal is the point |
| Time realism | 8.5 | 2h tight; Battery Spencer parking can add 5-10 min |
| Narrative flow | 9.5 | Setup → ridge-crossing climax → beach finale; textbook arc |
| Scenic payoff | 10 | GGB from north, GGB from south beach, skyline, Lombard — max score |
| Variety balance | 8.0 | Viewpoint-heavy; one food/neighborhood stop would raise this |
| Practical usability | 7.5 | Battery Spencer lot fills at golden hour; fog risk; medium friction |

**`tour_absolute` composite: 90.0**

**Layer B intent fits:**

| Intent | Composite | Notes |
|---|---|---|
| scenic_sunset | 97 | Time-of-day alignment is perfect across all 3 bridge stops |
| romantic | 91 | Sunset, bridge, beach; fog risk is the only deduction |
| photo_heavy | 95 | Every stop is a hero shot |

**Final blend (pure_curation):** **90.0**
**Final blend (hybrid_default, scenic_sunset intent):** `0.6 × 90 + 0.4 × 97` = **92.8**

---

## Tour 4 — "River Architecture + Loop"

**City:** Chicago
**Archetype:** Architecture-focused (hybrid walking/cruise)
**Target duration:** 3 hours
**Target user:** Architecture-curious visitor. Works for design-literate solo travelers, couples, and confident first-timers who can skip the shopping tour.
**Start:** Art Institute (lion statues) · **End:** Navy Pier at dusk
**Intent tags:** `architecture`, `architecture_modern`, `first_time_highlights`

**Route logic.** Chicago is the city where skyscrapers were invented, and its best self-presentation is river-level. The Chicago Architecture Foundation River Cruise is the single highest-rated tourist activity in the US, and wrapping it with the Loop's greatest-hits (Art Institute, Millennium Park, the Riverwalk, and Magnificent Mile) makes a perfect architecture day. The cruise is the set piece; everything else feeds into or out of it.

### Stop sequence

| # | Name | stop_type | iconicity | scenic | story | dwell (min) | friction | best_time | cluster |
|---|---|---|---|---|---|---|---|---|---|
| 1 | Art Institute lions + exterior | icon | 8 | 7 | 9 | 15 | low | any | chi_loop |
| 2 | Cloud Gate (The Bean) | icon | 10 | 9 | 7 | 15 | low | midday | chi_loop |
| 3 | Pritzker Pavilion (Gehry) + Lurie Garden | icon | 8 | 8 | 9 | 15 | low | any | chi_loop |
| 4 | Riverwalk (DuSable Bridge descent) | waterfront | 8 | 9 | 9 | 30 | low | any | chi_river |
| 5 | Chicago Architecture Foundation River Cruise | scenic_drive | 10 | 10 | 10 | 90 | low | afternoon | chi_river |
| 6 | Tribune Tower + Wrigley Building | icon | 9 | 8 | 10 | 10 | low | any | chi_river |
| 7 | Magnificent Mile walk to Navy Pier | neighborhood | 7 | 6 | 7 | 20 | low | afternoon | chi_north |
| 8 | Navy Pier at dusk (Ferris wheel lit) | viewpoint | 8 | 8 | 6 | 30 | medium | night | chi_north |

**Signature moments.**

- **Opening:** Touching a Chicago Art Institute bronze lion — 130 years of city ritual.
- **Primary payoff:** The river cruise. 90 minutes of river-level storytelling through the most architecturally-significant 1 mile of skyline on earth.
- **Secondary peak:** Standing on DuSable Bridge between Tribune Tower and the Wrigley Building.
- **Ending:** Navy Pier Ferris wheel lighting up as the skyline glows behind it.

**User-facing description.** "Chicago the way architects see it — Bean, river cruise, and a Ferris wheel finish."

### Benchmark score breakdown

**Layer A:**

| Dimension | Score | Notes |
|---|---|---|
| Iconic value | 9.5 | Bean + Pritzker + river cruise + Tribune Tower + Navy Pier |
| Geographic coherence | 9.5 | One continuous south-to-north spine along the river |
| Time realism | 8.0 | 3h with a 90-min cruise is tight — realistically 3h15 |
| Narrative flow | 9.5 | Build-up (Loop) → set piece (cruise) → cool-down (Mag Mile) → visual finale |
| Scenic payoff | 9.5 | Cruise alone is a 10; supporting stops average 8 |
| Variety balance | 8.5 | Icon + waterfront + scenic_drive + viewpoint |
| Practical usability | 8.0 | Cruise needs reservation; Navy Pier parking is medium friction |

**`tour_absolute` composite: 91.0**

**Layer B intent fits:**

| Intent | Composite | Notes |
|---|---|---|
| architecture | 97 | Pretty much designed as an architecture tour; story_richness max |
| architecture_modern | 94 | Pritzker, Bean, cruise stops include modern towers; period a bit mixed |
| first_time_highlights | 89 | Covers Chicago's top-5 but misses Willis Tower Skydeck |

**Final blend (hybrid_default, architecture intent):** `0.6 × 91 + 0.4 × 97` = **93.4**

---

## Tour 5 — "Condesa-Roma Taco Crawl"

**City:** Mexico City (CDMX)
**Archetype:** Food + neighborhood texture
**Target duration:** 3.5 hours
**Target user:** Food-interested traveler wanting the real CDMX — not tourist-Zócalo. Solo, couple, or small group. Adventurous eaters.
**Start:** Parque México (Condesa) · **End:** Mercado Roma or La Docena (Roma Norte)
**Intent tags:** `food_heavy`, `local_flavor`, `hidden_gems`

**Route logic.** Condesa and Roma are CDMX's adjacent leafy neighborhoods — walkable, lunch-tree-lined, and packed with the city's best casual eating. The route stitches five food stops across eight blocks with neighborhood texture (Art Deco buildings, bookstores, galleries) between each, ending at a market for dessert + souvenir. No tourist concessions; every stop is where CDMX locals actually eat.

### Stop sequence

| # | Name | stop_type | iconicity | scenic | story | dwell (min) | friction | best_time | cluster |
|---|---|---|---|---|---|---|---|---|---|
| 1 | Parque México (Condesa) | park | 5 | 7 | 7 | 15 | low | midday | cdmx_condesa |
| 2 | Tacos Hola El Güero (pastor taqueria) | food | 4 | 5 | 9 | 30 | low | midday | cdmx_condesa |
| 3 | Avenida Amsterdam Art Deco stroll | neighborhood | 4 | 8 | 8 | 20 | low | any | cdmx_condesa |
| 4 | Café Nin or Panadería Rosetta — pastries | food | 6 | 6 | 8 | 25 | low | midday | cdmx_roma |
| 5 | Casa Lamm + Plaza Río de Janeiro | neighborhood | 5 | 7 | 7 | 15 | low | afternoon | cdmx_roma |
| 6 | Contramar — tostadas + lunch | food | 7 | 6 | 8 | 60 | low | midday | cdmx_roma |
| 7 | Álvaro Obregón bookstores + cafés | neighborhood | 4 | 6 | 6 | 15 | low | any | cdmx_roma |
| 8 | Mercado Roma or La Docena | food | 5 | 6 | 8 | 30 | low | afternoon | cdmx_roma |

**Signature moments.**

- **Opening:** Street taco from Tacos Hola — the moment the trip feels real.
- **Mid-tour texture:** Avenida Amsterdam's Art Deco ring road, circling the old racetrack that became Condesa.
- **Lunch crescendo:** Tostadas de atún at Contramar. Universally considered CDMX's best neighborhood-restaurant moment.
- **Ending:** Mercado Roma's mezcal counter or La Docena's Sunday lunch — closes the loop on eating like a local.

**User-facing description.** "CDMX without the tourist stops — five taquerias, two Art Deco blocks, and the city's best neighborhood lunch."

### Benchmark score breakdown

**Layer A:**

| Dimension | Score | Notes |
|---|---|---|
| Iconic value | 6.5 | Deliberately low — this is not an icon tour |
| Geographic coherence | 9.5 | Tight 8-block walking route; zero transit |
| Time realism | 9.0 | 3.5h for 4 food stops + walking is realistic |
| Narrative flow | 9.0 | Warm-up taco → pastry → cultural pause → lunch peak → market finish |
| Scenic payoff | 7.5 | Art Deco walk + leafy streets; not view-heavy by design |
| Variety balance | 9.0 | Food + neighborhood + park alternating — the ideal mix |
| Practical usability | 9.0 | Flat, safe, walkable, weather-resilient, no reservations required except Contramar |

**`tour_absolute` composite: 85.5**

**Layer B intent fits:**

| Intent | Composite | Notes |
|---|---|---|
| food_heavy | 96 | 4 food stops of varied type; CDMX's best eating cluster |
| local_flavor | 94 | Zero tourist stops; Avenida Amsterdam, Álvaro Obregón — local corridors |
| hidden_gems | 88 | Contramar is somewhat known; rest are local-level |

**Final blend (pure_curation):** **85.5**
**Final blend (pure_custom, food_heavy intent):** `0.4 × 85.5 + 0.6 × 96` = **91.8**

---

## Tour 6 — "Manhattan Classics"

**City:** New York City
**Archetype:** First-time greatest-hits
**Target duration:** 4 hours
**Target user:** First-time NYC visitor with one day. Solo, couple, or tourist pair.
**Start:** Grand Central Terminal · **End:** Brooklyn Bridge pedestrian walkway (midpoint view)
**Intent tags:** `first_time_highlights`, `photo_heavy`, `architecture`

**Route logic.** NYC's canonical first tour is a south-running Midtown-to-Downtown spine. Start inside Grand Central for the Beaux-Arts opener, pass through Bryant Park's library steps, accept the Times Square gauntlet as a "did it" checkbox, descend via the High Line for the modern-park palate cleanser, then cross SoHo and Chinatown to end on the Brooklyn Bridge at golden hour. Four hours, all walking, hits 10 of the city's top-15 canonical stops.

### Stop sequence

| # | Name | stop_type | iconicity | scenic | story | dwell (min) | friction | best_time | cluster |
|---|---|---|---|---|---|---|---|---|---|
| 1 | Grand Central Terminal | icon | 9 | 8 | 10 | 20 | low | any | nyc_midtown |
| 2 | Bryant Park + NYPL lions | neighborhood | 8 | 7 | 9 | 15 | low | any | nyc_midtown |
| 3 | Times Square | icon | 10 | 6 | 7 | 15 | low | any | nyc_midtown |
| 4 | The High Line (south entry at Gansevoort) | park | 9 | 9 | 8 | 45 | low | afternoon | nyc_chelsea |
| 5 | Chelsea Market (Los Tacos No. 1 pause) | food | 7 | 6 | 7 | 30 | low | midday | nyc_chelsea |
| 6 | Washington Square Park + NYU Arch | neighborhood | 8 | 7 | 8 | 20 | low | any | nyc_village |
| 7 | SoHo cast-iron district (Prince & Greene) | neighborhood | 8 | 8 | 8 | 25 | low | any | nyc_downtown |
| 8 | Lombardi's or Prince Street Pizza | food | 6 | 5 | 7 | 20 | low | midday | nyc_downtown |
| 9 | Little Italy / Chinatown Mulberry → Mott | neighborhood | 7 | 7 | 8 | 25 | low | any | nyc_downtown |
| 10 | Brooklyn Bridge pedestrian entrance → midpoint | icon | 10 | 10 | 9 | 30 | low | golden_hour | nyc_bridge |

**Signature moments.**

- **Opening:** Stepping into Grand Central's main concourse — the clock, the zodiac ceiling, the scale.
- **Mid-tour palate cleanser:** Walking the High Line at afternoon light — a modern-park counterpoint to the classical opener.
- **Food stop:** A slice at Lombardi's or Prince Street.
- **Ending:** Halfway onto the Brooklyn Bridge walkway at golden hour — skyline, river, sunset.

**User-facing description.** "The perfect first Manhattan day — Grand Central to Brooklyn Bridge, with a slice along the way."

### Benchmark score breakdown

**Layer A:**

| Dimension | Score | Notes |
|---|---|---|
| Iconic value | 9.5 | Grand Central, Times Square, High Line, Brooklyn Bridge |
| Geographic coherence | 9.5 | Clean north-to-south spine; no backtrack |
| Time realism | 8.0 | 4h is realistic but requires not lingering; maybe 4h15 |
| Narrative flow | 9.5 | Classical opener → modern park → neighborhood texture → bridge finale |
| Scenic payoff | 9.0 | Grand Central interior + Brooklyn Bridge skyline are visual peaks |
| Variety balance | 9.5 | Icon + neighborhood + park + food + bridge — full spectrum |
| Practical usability | 8.5 | All walking, all flat, transit backup at every point |

**`tour_absolute` composite: 92.0**

**Layer B intent fits:**

| Intent | Composite | Notes |
|---|---|---|
| first_time_highlights | 96 | Hits canonical top-5 NYC stops with room to photograph them |
| photo_heavy | 91 | Grand Central, High Line, SoHo, Brooklyn Bridge all photo-tier |
| architecture | 88 | Grand Central + SoHo cast-iron + Brooklyn Bridge; moderately period-varied |

**Final blend (pure_curation):** **92.0**
**Final blend (hybrid_default, first_time intent):** `0.6 × 92 + 0.4 × 96` = **93.6**

---

## Tour 7 — "Right Bank After Dark"

**City:** Paris
**Archetype:** Romantic evening
**Target duration:** 2.5 hours
**Target user:** Couple on a Paris date night; post-dinner stroll. Dressed for it. Phones down. Wine before, wine after.
**Start:** Place Vendôme · **End:** Trocadéro with Eiffel sparkle at 10pm
**Intent tags:** `romantic`, `scenic_sunset` (night variant), `photo_heavy`

**Route logic.** Paris at night is a different city. This walk connects the Right Bank's three most cinematic nocturnal scenes — Place Vendôme's column, the Palais Royal arcades, and the Louvre's lit pyramid — crosses Pont des Arts for the Seine reflection, then rides the Quais to end at Trocadéro where the Eiffel Tower sparkles on the hour. Every 15 minutes of the walk is a hero shot. Designed for 9:30-10pm start to catch the 10pm tower sparkle as the finale.

### Stop sequence

| # | Name | stop_type | iconicity | scenic | story | dwell (min) | friction | best_time | cluster |
|---|---|---|---|---|---|---|---|---|---|
| 1 | Place Vendôme (column lit) | icon | 8 | 9 | 8 | 10 | low | night | paris_right |
| 2 | Palais Royal gardens (Colonnes de Buren) | neighborhood | 7 | 9 | 8 | 15 | low | night | paris_right |
| 3 | Louvre Cour Napoléon (pyramid lit) | icon | 10 | 10 | 9 | 15 | low | night | paris_right |
| 4 | Pont des Arts (Seine crossing) | viewpoint | 8 | 10 | 8 | 10 | low | night | paris_seine |
| 5 | Quai de Conti → Institut de France | scenic_drive | 6 | 8 | 7 | 10 | low | night | paris_seine |
| 6 | Pont Alexandre III (most ornate bridge) | icon | 9 | 10 | 8 | 15 | low | night | paris_seine |
| 7 | Quai Branly riverside promenade | waterfront | 7 | 9 | 6 | 15 | low | night | paris_seine |
| 8 | Trocadéro — Eiffel at 10pm sparkle | icon | 10 | 10 | 9 | 30 | low | night | paris_eiffel |

**Signature moments.**

- **Opening:** Place Vendôme's column against the lit Ritz facade — quiet glamour.
- **First peak:** Louvre Cour Napoléon at night — the pyramid glows, no crowd, no ticket.
- **Bridge sequence:** Pont des Arts → Pont Alexandre III — the city's two most romantic crossings in one walk.
- **Ending:** 10pm Eiffel sparkle from Trocadéro terrace. Five minutes of gold on steel.

**User-facing description.** "Paris after dark — Vendôme, the lit Louvre pyramid, and a 10pm Eiffel sparkle finish."

### Benchmark score breakdown

**Layer A:**

| Dimension | Score | Notes |
|---|---|---|
| Iconic value | 9.5 | Louvre + Pont Alexandre III + Eiffel — three top-tier night icons |
| Geographic coherence | 9.0 | East-to-west Right Bank sweep; clean |
| Time realism | 9.0 | 2.5h for 1.5 mi walking with pauses — very realistic |
| Narrative flow | 9.5 | Build-up → Seine crossings → Eiffel finale; classic three-act |
| Scenic payoff | 10 | Every stop is a lit hero shot |
| Variety balance | 7.0 | Icon + viewpoint + bridge; no food/neighborhood texture (by design) |
| Practical usability | 8.5 | Safe, flat, lit; only risk is Eiffel crowd at sparkle time |

**`tour_absolute` composite: 90.5**

**Layer B intent fits:**

| Intent | Composite | Notes |
|---|---|---|
| romantic | 97 | Designed as a date; lit icons, bridges, sparkle finale |
| scenic_sunset (night variant) | 93 | Time-of-day fit near-perfect for post-sunset walks |
| photo_heavy | 94 | Night photography heaven |

**Final blend (pure_curation):** **90.5**
**Final blend (hybrid_default, romantic intent):** `0.6 × 90.5 + 0.4 × 97` = **93.1**

---

## Tour 8 — "National Mall for Kids"

**City:** Washington DC
**Archetype:** Family-friendly highlights
**Target duration:** 3.5 hours
**Target user:** Family with kids 6-12. Stroller-friendly. Need food, bathrooms, shade. First DC visit.
**Start:** Lincoln Memorial · **End:** Air & Space Museum
**Intent tags:** `kid_friendly`, `first_time_highlights`, `minimal_walking` (moderate, not strict)

**Route logic.** DC's National Mall is the rare city core designed as a 2-mile pedestrian corridor with world-class museums and monuments bookending it. Start at Lincoln (wow opener for kids) and work east. Everything is free. Bathrooms and water fountains every 5 minutes. Air & Space is the kid-climax museum — it has to be the finale, not the opener, or energy collapses before the planes. Stroller-friendly, shade-manageable with early start, built-in lunch pause at a museum café.

### Stop sequence

| # | Name | stop_type | iconicity | scenic | story | dwell (min) | friction | best_time | cluster |
|---|---|---|---|---|---|---|---|---|---|
| 1 | Lincoln Memorial | icon | 10 | 8 | 10 | 20 | low | morning | dc_mall_west |
| 2 | Reflecting Pool walk east | park | 9 | 9 | 8 | 15 | low | morning | dc_mall_west |
| 3 | WWII Memorial | icon | 7 | 8 | 8 | 10 | low | morning | dc_mall_central |
| 4 | Washington Monument exterior | icon | 10 | 8 | 8 | 10 | low | morning | dc_mall_central |
| 5 | National Museum of American History | museum | 8 | 6 | 10 | 45 | low | midday | dc_mall_central |
| 6 | Museum café lunch (Mitsitam or American History) | food | 4 | 5 | 6 | 40 | low | midday | dc_mall_central |
| 7 | Natural History — Hope Diamond + dinosaurs | museum | 8 | 7 | 10 | 30 | low | midday | dc_mall_central |
| 8 | Capitol Reflecting Pool + Capitol exterior | icon | 10 | 9 | 10 | 15 | low | afternoon | dc_mall_east |
| 9 | Air & Space Museum — Apollo + Wright Flyer | museum | 10 | 8 | 10 | 50 | low | afternoon | dc_mall_east |

**Signature moments.**

- **Opening:** Climbing the steps of the Lincoln Memorial. Even 6-year-olds feel this one.
- **Kid set piece #1:** Hope Diamond + T-Rex at Natural History.
- **Kid set piece #2:** Touching a moon rock and standing under the Wright Flyer at Air & Space.
- **Framing moment:** Washington Monument at the midpoint — the visual spine of the whole walk.

**User-facing description.** "DC for kids — Lincoln, dinosaurs, Hope Diamond, and a moon rock finish. All free, all flat, all shaded."

### Benchmark score breakdown

**Layer A:**

| Dimension | Score | Notes |
|---|---|---|
| Iconic value | 9.0 | Lincoln + Washington + Capitol + Air & Space — DC's canonical icons |
| Geographic coherence | 10 | Literal 2-mile straight line west-to-east |
| Time realism | 8.0 | 3.5h is tight with kids; more realistic at 4h |
| Narrative flow | 9.0 | Monuments warmup → museum variety → Air & Space kid-climax |
| Scenic payoff | 8.5 | Reflecting Pool + Washington Monument carry the visual; museums are interior |
| Variety balance | 9.5 | Icon + park + food + museum — full kid-spectrum |
| Practical usability | 10 | All free, stroller-perfect, bathrooms everywhere, weather shaded options |

**`tour_absolute` composite: 89.0**

**Layer B intent fits:**

| Intent | Composite | Notes |
|---|---|---|
| kid_friendly | 96 | Designed for kids end to end — bathrooms, snacks, energy arc |
| first_time_highlights | 92 | DC's canonical top-5 all hit |
| minimal_walking | 78 | 2 miles flat with seats; not strict-minimal but family-pace realistic |

**Final blend (pure_curation):** **89.0**
**Final blend (pure_custom, kid_friendly hard intent):** `0.4 × 89 + 0.6 × 96` = **93.2**

---

## Tour 9 — "Shimokitazawa Drift"

**City:** Tokyo
**Archetype:** Local flavor / hidden-gems-lite
**Target duration:** 3 hours
**Target user:** Second-time Tokyo visitor (or first-time who's been warned off Shibuya/Shinjuku). Solo or couple. Coffee-literate, vintage-curious.
**Start:** Shimokitazawa Station · **End:** Chazawa Dori izakaya row at dusk
**Intent tags:** `hidden_gems`, `local_flavor`, `food_heavy` (soft)

**Route logic.** Shimokitazawa is the Tokyo neighborhood every local recommends but no tourist finds on their own. It's six minutes from Shibuya by train, low-rise, walkable in 90 minutes end to end, and packed with independent coffee, vintage clothing, izakaya alleys, and small theaters. No icons, low friction, high authenticity. The drift pattern — loops rather than a spine — matches how the neighborhood works; you don't "do" Shimokita, you wander it.

### Stop sequence

| # | Name | stop_type | iconicity | scenic | story | dwell (min) | friction | best_time | cluster |
|---|---|---|---|---|---|---|---|---|---|
| 1 | Shimokitazawa Station — Reload complex | neighborhood | 3 | 7 | 7 | 15 | low | any | shimokita_core |
| 2 | Ogawa Coffee Laboratory or Bear Pond Espresso | food | 4 | 5 | 7 | 25 | low | morning | shimokita_core |
| 3 | North exit vintage row (Flamingo, New York Joe) | neighborhood | 4 | 7 | 7 | 40 | low | any | shimokita_north |
| 4 | Shimokita Senroichigai (old rail market) | neighborhood | 3 | 8 | 8 | 20 | low | any | shimokita_core |
| 5 | Magnet Coffee / Mikan Shimokita food hall | food | 4 | 6 | 7 | 30 | low | midday | shimokita_core |
| 6 | Honda Gekijo / small-theater row | neighborhood | 3 | 6 | 8 | 15 | low | any | shimokita_south |
| 7 | Chazawa Dori / Suzunari alley izakaya | food | 5 | 7 | 9 | 45 | low | night | shimokita_south |

**Signature moments.**

- **Coffee opener:** Bear Pond's gibraltar — the moment the day feels right.
- **Texture peak:** The "senroichigai" — old rail line turned market corridor.
- **Vintage set piece:** New York Joe Exchange — the flagship vintage basement with a skate ramp.
- **Ending:** Chazawa Dori at 6pm, paper lanterns lighting, yakitori smoke, and a first beer. Classic Tokyo micro-scene.

**User-facing description.** "The Tokyo neighborhood locals send their friends to — coffee, vintage, small theaters, and an izakaya alley dinner."

### Benchmark score breakdown

**Layer A:**

| Dimension | Score | Notes |
|---|---|---|
| Iconic value | 4.5 | Deliberately low — none of these are canonical Tokyo icons |
| Geographic coherence | 9.0 | Compact loops; no transit between stops |
| Time realism | 9.0 | 3h is realistic with dwells; easy to stretch or shrink |
| Narrative flow | 8.5 | Coffee → vintage → market → food → night finale; clear arc |
| Scenic payoff | 7.5 | Texture-heavy, not view-heavy; railway market + lantern alley are the peaks |
| Variety balance | 9.5 | Food + neighborhood + food + neighborhood + food — reinforcing, not repetitive |
| Practical usability | 9.5 | Flat, safe, English-signed enough, weather-indoor-friendly |

**`tour_absolute` composite: 85.5**

**Layer B intent fits:**

| Intent | Composite | Notes |
|---|---|---|
| hidden_gems | 97 | Iconicity inversion rewards avoiding top icons — scoring table tuned for exactly this |
| local_flavor | 96 | Every stop is where locals actually go; zero tourist concession |
| food_heavy | 85 | 3 food stops, balanced not dominant |

**Final blend (pure_curation):** **85.5**
**Final blend (pure_custom, hidden_gems intent):** `0.4 × 85.5 + 0.6 × 97` = **92.4**

**Calibration note.** This tour is the hidden_gems exemplar. Its low iconic_value (4.5) looks bad in absolute terms but scores 97 on intent fit because the hidden_gems weighting *inverts iconicity*. If the scoring engine fails to score this tour well, the intent-fit weighting is miscalibrated.

---

## Tour 10 — "Causeway Miami"

**City:** Miami
**Archetype:** 2-hour ultra-efficient
**Target duration:** 2 hours
**Target user:** Visitor with one evening and a rental car. Hotel in Miami Beach or Downtown. Wants to feel like they saw Miami.
**Start:** South Pointe Park · **End:** Vizcaya exterior at golden hour
**Intent tags:** `efficient_short`, `first_time_highlights`, `scenic_sunset`

**Route logic.** Miami's single best 2-hour experience is the three-causeway crossings — Ocean Drive Art Deco → MacArthur Causeway bay → Downtown skyline → Rickenbacker bay-view → Coconut Grove. Every causeway is a water-crossing scenic drive; every neighborhood switch reveals a different Miami. End at Vizcaya's exterior for a Mediterranean-estate-on-Biscayne-Bay sunset finale. No stops require tickets; no parking headaches; it's Miami's canonical first-timer drive in 2h with zero dead miles.

### Stop sequence

| # | Name | stop_type | iconicity | scenic | story | dwell (min) | friction | best_time | cluster |
|---|---|---|---|---|---|---|---|---|---|
| 1 | South Pointe Park pier | waterfront | 7 | 9 | 7 | 15 | low | afternoon | miami_sobe |
| 2 | Ocean Drive Art Deco strip (drive-through) | scenic_drive | 9 | 8 | 9 | 10 | low | afternoon | miami_sobe |
| 3 | MacArthur Causeway (cruise + Star Island views) | scenic_drive | 8 | 9 | 7 | 10 | low | afternoon | miami_bay |
| 4 | PAMM + Downtown skyline drive-by | viewpoint | 7 | 8 | 7 | 10 | low | afternoon | miami_downtown |
| 5 | Brickell Ave skyline + Rickenbacker on-ramp | scenic_drive | 7 | 8 | 6 | 10 | low | afternoon | miami_brickell |
| 6 | Hobie Beach / Rickenbacker pullover | viewpoint | 6 | 10 | 5 | 15 | low | golden_hour | miami_key |
| 7 | Coconut Grove waterfront drive | scenic_drive | 6 | 8 | 7 | 10 | low | afternoon | miami_grove |
| 8 | Vizcaya Museum & Gardens — exterior | icon | 8 | 9 | 9 | 20 | medium | golden_hour | miami_grove |

**Signature moments.**

- **Opening:** Art Deco lifeguard huts on Ocean Drive — postcard Miami in the first 10 minutes.
- **Bay crossing:** MacArthur Causeway with cruise ships on the left and Star Island mansions on the right.
- **Sunset setup:** Rickenbacker pullover — the skyline lit across the bay.
- **Finale:** Vizcaya's Italianate facade against Biscayne Bay at golden hour.

**User-facing description.** "Miami in 2 hours — Ocean Drive, three causeway crossings, and a Vizcaya sunset finish."

### Benchmark score breakdown

**Layer A:**

| Dimension | Score | Notes |
|---|---|---|
| Iconic value | 8.0 | South Beach + Vizcaya + skyline; no ultra-top tier but solid |
| Geographic coherence | 9.0 | Clean 3-causeway arc, no backtracks |
| Time realism | 9.5 | Under-budget-likely; 1h50-2h with traffic |
| Narrative flow | 9.0 | Deco opener → bay crossings → skyline → sunset finale |
| Scenic payoff | 9.5 | Causeway x 3 + skyline + Vizcaya golden hour |
| Variety balance | 8.5 | Waterfront + scenic_drive heavy; one icon + one viewpoint balance |
| Practical usability | 8.5 | Some friction at Vizcaya lot; rest is drive-through |

**`tour_absolute` composite: 89.0**

**Layer B intent fits:**

| Intent | Composite | Notes |
|---|---|---|
| efficient_short | 95 | Designed for 2h; duration realism is max; every minute is a payoff |
| first_time_highlights | 89 | Hits Miami's top water crossings + Deco + Vizcaya |
| scenic_sunset | 92 | Time-of-day fit is strong through the final 45 min |

**Final blend (pure_curation):** **89.0**
**Final blend (hybrid_default, efficient_short intent):** `0.6 × 89 + 0.4 × 95` = **91.4**

---

## Summary table — all 10 gold tours

| # | Tour | City | Archetype | Duration | tour_absolute | Primary intent fit | Final (hybrid) |
|---|---|---|---|---|---|---|---|
| 1 | Mulholland to the Pacific | LA | Iconic driving | 2h | 90.0 | 93 (sunset) | 91.2 |
| 2 | Centro Storico Classics | Rome | Iconic walking | 4h | 93.0 | 97 (first_time) | 94.6 |
| 3 | Golden Hour Bay Loop | SF | Scenic sunset | 2h | 90.0 | 97 (sunset) | 92.8 |
| 4 | River Architecture + Loop | Chicago | Architecture | 3h | 91.0 | 97 (architecture) | 93.4 |
| 5 | Condesa-Roma Taco Crawl | CDMX | Food/neighborhood | 3.5h | 85.5 | 96 (food_heavy) | 91.8 (pure_custom) |
| 6 | Manhattan Classics | NYC | First-time | 4h | 92.0 | 96 (first_time) | 93.6 |
| 7 | Right Bank After Dark | Paris | Romantic | 2.5h | 90.5 | 97 (romantic) | 93.1 |
| 8 | National Mall for Kids | DC | Family | 3.5h | 89.0 | 96 (kid_friendly) | 93.2 (pure_custom) |
| 9 | Shimokitazawa Drift | Tokyo | Local flavor | 3h | 85.5 | 97 (hidden_gems) | 92.4 (pure_custom) |
| 10 | Causeway Miami | Miami | 2h efficient | 2h | 89.0 | 95 (efficient_short) | 91.4 |

**Calibration summary.**

- 10 of 10 score `tour_absolute ≥ 85` ✅
- 6 of 10 score `tour_absolute ≥ 90` (target was 7) — retune `narrative_flow` + `scenic_payoff` upward slightly at next calibration pass
- 10 of 10 score primary intent_fit ≥ 93 ✅
- Intent-fit inversion verified on Tour 9 (Shimokita) — low iconicity correctly rewarded by hidden_gems weighting

**Next calibration loop:** score 50 AI-generated tours per archetype × city, confirm median lands in 60-75 range, and confirm no AI tour exceeds any gold tour on both absolute and primary intent fit simultaneously.

---

**Version:** v1 · starting weights · calibration set.
**Depends on:** [tour-scoring-spec.md](./tour-scoring-spec.md) (scoring dimensions + formulas), [featured-tours-research.md](./featured-tours-research.md) (stop-attribute source data for all 10 cities).
