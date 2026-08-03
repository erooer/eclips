# The Ominous Below — Art Bible and Commission Brief

## Purpose and evidence

This is a visual-design brief for the existing custom dungeon **The Ominous Below**. It is written for a concept artist or sprite artist who has not played the game. It distinguishes the **implemented facts** (map layout, encounter names, mechanics, sizes, and current assets) from **art direction** (the recommended visual realization of those facts).

The current implementation is gameplay-complete but visually provisional. Every moving custom creature currently uses the same animated encounter placeholder (`chars16x16dEncounters2`, index 96). Most static objectives and the portal use a shared `lofiObj5` placeholder. The map currently uses one floor tile, `1GroundOmen1`, and one wall tile, `1CreepyWall1`. Consequently, names, combat roles, map structure, and reward descriptions are authoritative; detailed costume, material, color, and environmental descriptions below are the recommended brief for replacing those placeholders.

The dungeon is a non-persistent, difficulty-8 instance measuring **115 × 61 tiles**. It is built as a left-to-right descent through three distinct spaces: drowned maze, prison, and abyssal ritual sanctum.

## General overview

**Premise.** The Ominous Below is an ancient processing ground beneath reality: a drowned underworld route that has been converted into a prison and finally into a living ritual chamber. Souls are ferried inward, judged and bound, then offered to a primordial intelligence called the Ominous One.

**Player experience.** The intended emotional curve is curiosity → confinement → dread → revelation. The first third asks players to navigate a maze and extinguish lights. The middle third turns the theme into incarceration: wardens, chains, gaolers, and sealed passages. The final third is not merely another prison room; it is the place for which the prison exists, an abyssal eye-ritual that feels much older than its captors.

**Difficulty and length.** It is a high-end, multi-boss dungeon. A full clear contains three major bosses—The Faceless Ferryman, Veyra, Warden of Chains, and The Ominous One—plus three mandatory objective gates (lanterns, gaolers, seals) and boss-specific anchors or pillars. The map is deliberately long and horizontally progressive rather than branching into alternate routes.

**Visual identity.** The core image is *cold violet light trapped inside wet black stone*. Repeated motifs are chain links, hooded silhouettes, soul lanterns, barred thresholds, downward-pointing architecture, circular ritual geometry, and small points of pale light in overwhelming darkness. It should feel like a submerged gothic underworld, not a natural cave and not a conventional medieval castle.

**Reference vocabulary, not a required direct imitation.** The implementation’s names evoke a mythic river crossing, penitentiary gothic architecture, condemned souls, and an eldritch abyss. Visually, combine the readable, high-contrast pixel-art language of a top-down action RPG with drowned-cathedral, underworld-ferry, and cosmic-horror imagery.

## Lore

The Ominous Below was once a **transit and processing complex for the dead**. A river route carried souls through a maze of drowned channels, and the Faceless Ferryman collected their toll. Later wardens turned the route into a prison: iron gaolers, oathbreaker judges, condemned oracles, and shackled revenants were installed to sort, bind, and punish those souls.

At its deepest point lies the older truth. The prison was constructed around a buried abyssal presence, not above an empty pit. The Ominous One feeds on the condemned. The four seals and later ritual pillars are containment devices as much as they are ritual equipment: the wardens have tried to keep the being dormant while still exploiting its hunger.

- **The Faceless Ferryman** is the threshold keeper. He is not simply a monster in a boat; he is the institution’s collector, moving souls from the flooded maze into the prison system. His missing face suggests an erased identity or a person who has become a role.
- **Veyra, Warden of Chains** is the prison’s living executioner. The title implies authority, but her encounter is also about imprisonment: she is protected by anchors and controlled by broken wards. She can be read as both warden and prisoner of the system she enforces.
- **The Ominous One** is the consuming intelligence at the end of the descent. Its dialogue—“The condemned will feed me,” then “Thy strength befits a crown”—frames it as proud, ancient, and ceremonial rather than animalistic.

Environmental storytelling should show this history in layers: older drowned masonry at the entrance, imposed iron prison hardware in the middle, and increasingly nonhuman geometry near the ritual chamber. The closer the player gets to the final boss, the less the architecture should look built for people.

## Player journey

### 1. Entrance: the drowned threshold

The player enters at the far western side of the 115-tile-wide map. The opening impression should be a low-ceilinged, flooded threshold with an uncertain route ahead. The room should be dim enough that lantern light is meaningful, but never so dim that collision or enemy silhouettes become unreadable.

Use an immediate landmark: a broken toll arch, a half-sunk skiff, or a suspended chain with a toll weight. The floor begins as wet, nearly black flagstone and shallow reflective water. The path ahead is a deliberately oversized maze rather than a narrow corridor.

### 2. Lantern maze: extinguishing the route

The first approximately 30 columns form the maze. Three **Ominous Soul Lanterns** are placed through the route and must be destroyed. The existing map has staggered internal walls, so the visual language should make wrong turns feel like a real maze: damp dividers, broken alcoves, recessed channels, and distant lanterns glimpsed through grating or open doorways.

Enemies establish the drowned-soul ecosystem:

- Drowned Pilgrims and Lantern Wraiths establish the human and spectral layers.
- Riverbound Hounds turn the path into an active pursuit space.
- Ferryman’s Attendants and a Soul Collector foreshadow the first boss.

Each extinguished lantern should make a localized area darker and release a small, upward drift of violet soul motes. Destroying all three removes the final maze partitions and opens the Ferryman’s arena. This is a substantial, cinematic transition: two full wall dividers vanish rather than a small door merely opening.

### 3. The Ferryman’s crossing

The Faceless Ferryman occupies the first boss space, centered around map x≈40. The arena should read as a drowned dock or soul-barge quay, even though the underlying map currently contains only floor and wall tiles. It is a pause after the maze: wider, symmetrical enough to dodge in, and dominated by a central water feature or mooring circle.

At partway through the fight, he calls forth two **Soul Barge Anchors**. They make him invulnerable until destroyed, suggesting that unseen barges or moored soul vessels are holding him in place and feeding him strength. When he falls, the entire divider at x=47 disappears and the prison opens.

### 4. The prison procession

The middle section, approximately x=48–80, is a wider prison gauntlet. It should become more vertical, engineered, and oppressive than the wet maze: ironwork, chains, barred arches, raised execution platforms, and cell-window silhouettes. The two gaolers are visible as high-status obstacles, not lost among ordinary enemies.

The First Gaoler and Last Gaoler gate Veyra’s vulnerability. Their names imply a ritualized custody sequence: the first opens the sentence; the last closes it. Place them as paired wardens on opposite sides or at successive prison stations, using matching visual language with contrasting silhouettes.

Veyra occupies the center of this section at x≈64. Her room is a chain court—an arena whose ceiling is implied by vertical chains disappearing upward into darkness. Once she dies, another entire divider at x=81 vanishes. The player should feel the prison infrastructure physically fail and reveal a deeper, less human void.

### 5. The abyssal approach

Beyond x=81, the dungeon changes from prison to ritual space. The existing final area contains Abyssal Remnants, an Ominous Eye, a Hollow Devourer, and four Ominous Seals arranged around the final boss. Visually, the walls should lose their regular masonry and become black, ribbed, geometric, or root-like. Use a faint violet underglow from cracks, a void-water sheen, and symbols that repeat the final boss’s eye/halo motif.

The four seals are the last access condition. Breaking all four makes the Ominous One vulnerable and announces that it has awakened. They should be unmistakable static ritual objects, each with a different small silhouette variation but one shared eye-and-chain insignia.

### 6. The Ominous One’s ritual chamber and completion

The final boss sits at x≈96, centered in a broad chamber. The room must support large circular projectile patterns, so the playable floor needs a clean, readable central disk, with decorative density pushed outward to the rim.

After the Ominous One dies, the implementation removes remaining enemies and projectiles and creates a short-lived **Ominous Completion Chest** containing the Mark of the Ominous One plus attack and defense potions. The map data still contains an `Ominous Return Portal` at the far eastern side; however, current encounter direction removes the return portal from the boss-room experience. Treat the chest as the intended visual endpoint, and do not make a return portal a focal piece unless the game design later restores it.

## Map structure and progression gates

The map is horizontally linear, with a maze-shaped first act and increasingly broad encounter rooms. There are no authored secret rooms, branching reward routes, checkpoints, or alternate exits in the current map data.

| Section | Approx. map span | Purpose | Gate condition | Transition visual |
| --- | ---: | --- | --- | --- |
| Drowned maze | x=1–29 | Navigation and lantern objectives | Destroy 3 Soul Lanterns | Two full stone partitions vanish at x=30 and x=32 |
| Ferryman arena | x=33–46 | First boss | Defeat Ferryman | Full divider vanishes at x=47 |
| Prison | x=48–80 | Gaolers, Veyra, chain theme | Defeat Veyra | Full divider vanishes at x=81 |
| Abyssal ritual sanctum | x=82–113 | Seals and final boss | Destroy 4 seals, then defeat Ominous One | Completion chest at x≈96, y≈25 |

The first maze contains internal wall runs at x=7, 13, 19, and 25, creating a serpentine route. The horizontal dungeon outline and full-height dividers make the downward journey feel inescapable even though the player moves east.

## Environment brief

### Built visual baseline

The current playable map supplies only the dark floor `1GroundOmen1` and wall `1CreepyWall1`; it does not presently author water, bridges, vegetation, cages, torches, statues, rubble, or ceiling décor. Those elements below are commission recommendations, not claims about existing sprite placement.

### Materials and architecture

- **Stone:** blue-black basalt or soot-dark slate, with cold indigo edge highlights. Avoid warm gray castle stone. Grout should read in 1–2 pixels, with damp violet staining in cracks.
- **Prison iron:** nearly black wrought iron with blue steel highlights, oxidized purple edges, and occasional pale silver chain wear. Bars should be chunky and readable, never a thin visual mesh.
- **Wood and boats:** waterlogged charcoal timber with pale desaturated lavender reflections. Use warped planks, thick rope, iron nails, and drip lines—never clean nautical wood.
- **Water:** black-violet, slow, reflective, and shallow around the maze/dock. It should reflect lanterns as broken vertical streaks rather than bright mirror images.
- **Abyssal material:** the final chamber may replace conventional stone with matte black plates, fissures of ultraviolet light, and impossible radial seams that all point toward the boss.

### Props and scenery by zone

**Maze / drowned route:** half-submerged toll posts, broken oars, ring-bolts, ruined mooring chains, leaning lantern poles, occasional small bone piles, and distant barred culverts. Mist lies low and moves laterally. A small number of dripping walls and pooled water tiles establish wetness without obscuring pathing.

**Ferryman dock:** a circular dock, two rotted boat silhouettes or ghost-barge moorings, oversized chain anchors, a toll bell, drowned travel offerings, and a central water void. The suggested environment tells players why anchors make the Ferryman invulnerable.

**Prison:** massive vertical chains, cell doors, restrained statues, cracked sentencing tablets, iron braziers with violet flame, suspended cages, broken padlocks, and narrow shafts of cold light. Use no flowers, grass, trees, or vines except perhaps a few dead, salt-stiff roots infiltrating very old masonry.

**Abyss:** floor rings, seal sockets, obelisk fragments, black pillars, thin fog that rises rather than settles, and a sparse halo of vertical spikes. No ordinary furniture. The geometry should be sparse near the fighting space and dense, alien, and receding at the room’s perimeter.

### Lighting and palette

Primary lighting should come from lanterns, seals, chains, and the final ritual—not from generic wall torches. The player should always be able to separate solid collision walls, safe floor, enemies, hostile bullets, and objectives at a glance.

Suggested palette:

- near-black: `#090A12` / `#10101B`
- blue-black stone: `#151B35` / `#222C50`
- cold steel: `#46536F` / `#8893B3`
- soul violet: `#8D5BDE` / `#B285FF`
- pale spectral cyan: `#A7E8FF`
- ritual magenta accent: `#D85DD1`
- danger / eye accent: `#E04567` or muted crimson `#9D2949`
- rare warm contrast for human remnants: `#B88952` / `#E0BE78`

## Enemy roster and sprite brief

All sizes below use the game’s existing logical scale (100 is a typical full tile-sized entity). “Current placeholder” is factual: animated enemies use `chars16x16dEncounters2:96`; static objectives use `lofiObj5:ff`.

| Enemy / objective | Current placeholder | Logical size | Purpose and recommended appearance |
| --- | --- | ---: | --- |
| Drowned Pilgrim | animated encounter 96 | 85 | Thin, stooped drowned traveler in shredded pilgrimage wraps; drooping hood, wet hem, lantern-less staff or broken oar. Blue-gray skin, muted teal rags, pale cyan eyes. Four-frame shamble, brief recoil, four-fan water/soul shot. Common human silhouette. |
| Lantern Wraith | animated encounter 96 | 80 | Floating hood or loose shroud with a suspended lantern core where the chest should be. Desaturated violet cloth, cyan flame, no legs. Gentle bob and flickering transparency. Its weakening beam should originate from the lantern core. |
| Riverbound Hound | animated encounter 96 | 90 | Low, long, amphibious corpse-hound: ribbed back, webbed paws, trailing water ribbons. Navy/green-black body with icy eye points. Crouch → flash → explosive charge animation. Immediate four-legged silhouette. |
| Ferryman’s Attendant | animated encounter 96 | 90 | Cloaked deckhand or drowned boatman carrying a pole-hook. Dark indigo coat, rope belt, masked head. Slow hovering drift and three-shot spread from its hook. Should visually belong to the Ferryman without duplicating his scale. |
| Soul Collector | animated encounter 96 | 115 | Tall hovering reaper with a wide cage-lantern or netted reliquary. Heavy silhouette, long sleeves, bone-white mask, violet trapped souls. Its spawned pilgrims should appear to spill from the cage. |
| Ominous Soul Lantern | `lofiObj5:ff` | 90 | A heavy iron lantern on a short plinth or chain, holding a trapped violet-white soul flame. Cracked glass, eye-shaped vents, chain collar. Static 2–3-frame flame; when broken, glass burst plus darkening smoke. High priority. |
| Soul Barge Anchor | `lofiObj5:ff` | 100 | Oversized black iron anchor embedded in a small spectral water pool, with taut chains leaving the room. Violet runes pulse along the shank. Static but with chain tension and water-ripple frames. |
| Shackled Revenant | animated encounter 96 | 90 | Reanimated prisoner, hunched under hand and ankle shackles, dragging a length of chain. Slate skin and bruise-purple cloth; orange-rust accent only if needed for readability. Four-shot slowing burst can appear as chain shards. |
| Oathbreaker Judge | animated encounter 96 | 100 | Floating robed magistrate with a blank porcelain or iron mask, broken scale, and gavel/staff. Palette: old ivory, black cloth, violet seal glow. Its armor-breaking beam should feel like a condemning verdict. |
| Iron Gaoler | animated encounter 96 | 120 | Broad armored jailer, rectangular torso, helmet slit, massive ring of keys and slab-like gauntlets. Black iron and cold steel. Two-part animation: still guard posture, then floor-slam shockburst. |
| Condemned Oracle | animated encounter 96 | 80 | Frail levitating seer with a sealed or covered face, torn ceremonial robes, and a hovering eye fragment. Pale violet and bone colors. Predictive shot comes from the eye, not a conventional weapon. |
| The First Gaoler | animated encounter 96 | 135 | Aggressive counterpart: plated shoulders, hooked halberd, forward-heavy silhouette, red-violet jail sigil. Six-shot fan reads as a commanded volley. Give it a first-key / opening-lock emblem. |
| The Last Gaoler | animated encounter 96 | 135 | Defensive counterpart: wider cloak or tower-shield silhouette, execution staff, final-lock emblem. Cooler blue-violet palette than the First Gaoler. Eight-shot pattern reads as a sealing barrage. |
| Chain Anchor | `lofiObj5:ff` | 90 | A waist-high rune anchor or prison pylon with four chains running outward/upward. Its core should match Veyra’s armor glow. Static 2–3-frame pulse and violent chain recoil on death. |
| Abyssal Remnant | animated encounter 96 | 80 | Fragment of a former prisoner dissolving into black smoke and violet shards. No solid lower body. Short, jagged, flickering silhouette. Six-shot pulse emerges from a central void. |
| Ominous Eye | animated encounter 96 | 85 | A floating, lidless eye wrapped in torn black lids or chained rings. Deep magenta iris and hot pale pupil. Distinct open/closed frames are essential: closed is invulnerable; open fires. |
| Hollow Devourer | animated encounter 96 | 105 | Low, wide abyss creature with a mouth-like void in its torso and several short hooked limbs. Dark navy silhouette with internal purple glow. Alternates hungry pursuit and wary retreat. |
| Ominous Seal | `lofiObj5:ff` | 90 | Four matching but individually damaged floor-standing seal monoliths: circular eye-glyph, chain border, cracked violet core. Do not make them look like generic candles. High priority. |
| Ritual Pillar | `lofiObj5:ff` | 100 | Tall, black, slightly tapered ritual obelisk with inset eye/chain glyphs and a pulsing violet heart. Four pillars appear only once in the final boss’s stagger. A destroyed version should leave smoking fragments, never respawn. Highest priority. |

## Bosses

### The Faceless Ferryman

**Role and scale.** The Ferryman is the first major boss, size 150: visibly larger than the attendants but still grounded in the drowned-route environment. His silhouette must read instantly as a tall boatman: broad hood/hat, long coat, long pole or hooked oar, and a lantern or toll relic.

**Face and body.** His hood should contain a smooth darkness or pale blank mask—not a conventional skull. The absence of facial features is the point: the player should see a human-shaped void framed by a collar or hood. Suggested body is gaunt and disproportionally tall, with long sleeves and only hints of hands. If hands are shown, make them gloved, drowned, or skeletal, not muscular.

**Clothing.** Layered boatman’s coat in charcoal, deep navy, and wet violet; asymmetric hems with water damage; braided rope sash; shoulder cape that reads as a barge sail in motion. The garment needs bright enough edge pixels to remain readable against black floors.

**Lantern, chains, and boat references.** A brass-black toll lantern is recommended at the waist, on a pole, or hanging from the boat hook. Its flame is pale cyan/violet rather than warm yellow. Two spectral anchor chains should emerge during Crossing and lead visually toward the Soul Barge Anchors. Include rivets, rope knots, chain links, and a small ferry token emblem. A faint crescent of ghost-water under his feet can suggest that he travels on an invisible skiff.

**Combat expression.** In “Toll of the Dead,” he advances slowly and attacks with a wide 180° wave plus tighter sprays, summoning drowned pilgrims. At 75% health, “Crossing” summons two anchors and temporarily makes him invulnerable. The art needs a clear protected state: lantern and chain runes brighten, coat billows upward, anchor chains become taut. In “The Price,” the room receives denser fan and predictive fire; make his hook/oar point toward the player just before the aimed shot.

**Animation plan.** Recommended 8-direction or 4-direction movement set with 4 walking frames; 3 idle cloth/lantern frames; 3 attack frames (wind-up, release, recovery); 2 Crossing-state frames with rising water and chain tension; 4 death frames where hood collapses, lantern extinguishes, and the body unravels into wet rags and soul sparks.

**Arena.** A drowned ferry pier or circular quay. Central dark water is safe only as visual dressing outside traversable tiles; keep all collision clear. The room should contain two visually obvious anchor sockets so the mechanic reads before the anchors spawn. Lighting is cyan-violet reflections, with black water surrounding the combat disk.

### Veyra, Warden of Chains

**Role and scale.** Veyra is size 160 and should be a taller, more imposing mid-boss than the Ferryman. She is an armored prison warden who is simultaneously bound by her own chains.

**Form and armor.** Use a female-coded or androgynous armored silhouette without relying on exposed skin: elongated pauldrons, segmented dark plate, tapered helm/crown, prison-key iconography, and a severe mantle. The armor should be iron-black with rich amethyst edge-lighting; the interior gaps glow cold violet as though something captive shines within.

**Chains and imprisonment.** Four enormous chains should be integral to her design. They may attach at wrists, back, collar, or a halo-like restraint behind her. They should feel painfully structural rather than decorative jewelry. In her chain phase, the four Chain Anchors become visible extensions of these restraints. She fights while the player must destroy the anchors; she should never look dormant or harmless during that phase.

**Movement and attacks.** In “Sentence,” she holds near her spawn as a judge/warden, alternating a tight fan and a larger secondary barrage while summoning Shackled Revenants. At 80% health, “Four Chains” begins: she remains invulnerable but continues firing rotating and spread attacks for roughly eleven seconds. This needs a strong attack pose—one hand drawing the chains taut, the other throwing chained light. “Prison Closes” is a denser sustained sentencing pattern, while “Broken Warden” is faster and more desperate below 35% health.

**Arena.** A chain court: smooth central floor for dodging, four floor sockets or wall rings for anchors, and chains vanishing into ceiling darkness. The light should seem to come from the restraints, producing narrow violet highlights on black iron.

**Animation plan.** 4 idle/floating frames with restrained chain sway; 3 firing frames with chain-whip recoil; 3 anchor-phase frames with violent pull and spinning runes; 4 death frames in which armor plates fall, chains snap upward, and the inner violet light escapes. Her death should visually justify an entire prison divider collapsing.

### The Ominous One

**Role and scale.** Size 200, the Ominous One is the dungeon’s final visual event. It must fill far more screen space than Veyra while retaining a readable center silhouette amid dense projectile patterns. It is a crowned abyssal sovereign, not simply a larger ghost.

**Body and proportions.** Recommended silhouette: enormous upper body tapering into a lower vortex or floating mantle; long asymmetrical arms; a broad, crown-like head or ringed crest; body about 1.5 times Veyra’s visual height with a compact, powerful central mass. Avoid a conventional humanoid giant. It should look as if the room’s darkness has congealed around an ancient ruler.

**Face and eyes.** Use one dominant central eye or a face partially eclipsed by a mask-like black void. The iris/pupil should be a high-value focal point—magenta-violet ring, pale or crimson slit—visible even at combat scale. A secondary set of small dim eyes can appear in cloak folds only during special phases, but the main eye must remain the readable boss identifier.

**Armor and crown.** Armor should be ancient, ceremonial, and fractured: black-blue plates, long pointed crown prongs, chain-inlaid rings, and eye-glyph filigree. The crown is important because the phase line is “Thy strength befits a crown.” The design should support a moment where crown geometry or halo segments awaken at 35% health.

**Aura and magic.** Surround the boss with a restrained violet-black aura rather than constant noisy particles. Use circular glyphs, orbiting broken chain links, ink-like vapor, and thin radial beams. The magic should be organized: perfect rings during barrages, deliberate seals during invulnerability, and a rotating gap pattern during the crown spiral.

**States and visual language.**

- **Dreaming Beneath:** dormant, invulnerable opening. Eye mostly closed; slow purple pulse; occasional eight-shot expression. It should appear like a statue/thing waking underneath the floor.
- **The Gaze:** eye opens fully. Dense 12-shot radial patterns and aimed shots emerge from the eye. This is the first clear reveal of personality.
- **Consume the Condemned:** invulnerable ritual, with Abyssal Remnants spawned around it for eight seconds. The boss should hold or draw spectral victims into itself; use inward-moving smoke, chain lines, and a taunt cue.
- **World Below Pillars:** four Ritual Pillars appear for a one-time interruption objective. The boss briefly uses the “...” taunt and should look staggered, quiet, and protected by the pillars. Pillars do not return once destroyed.
- **World Below Barrage:** after the pillars fall, the boss is invulnerable for ten-second fast barrages. The visual is a full circular 16-shot, fast radial ring: clean, symmetric, and much faster than ordinary fire. Make the source feel like a revolving crown or eye halo.
- **World Below Recovery:** a seven-second “...” stagger. This is the only damage window in this loop. The boss should visibly sag, lower its aura, dull its eye, and expose bright cracks/heart-light. It then returns to the invulnerable fast barrage; it does not summon pillars again.
- **Crowned Strength:** at 35% health or lower, a short 2.5-second invulnerable proclamation: “Thy strength befits a crown.” The crown unfolds, the eye brightens, and the arena prepares for the final spiral.
- **Crown Spiral:** alternating clockwise/counterclockwise three-second legs. Sixteen-shot volleys leave a narrow but readable moving gap. The rotation should reverse continuously rather than snap: clockwise 1→2→3→4, then counterclockwise 4→3→2→1. Use a luminous crown ring or moving halo to make the safe seam legible.

**Movement and idle.** The Ominous One should mostly hover near the ritual center, moving with small deliberate drifts rather than chasing. Idle pose: arms partially folded or hanging, mantle/void slowly inhaling, one eye half-lidded. It should never read as passive cute floating; stillness must feel imposing.

**Death animation.** The eye should over-brighten, the crown ring fracture outward, and the body collapse inward into a silent black disk before a final violet implosion. Do not use a generic gore death. The cleanup should leave a small, dignified residue—a cracked eye sigil or extinguished crown shards—before the completion chest appears.

**Final arena.** A circular black ritual floor with four seal stations around its perimeter and four pillar sockets farther out. Build the floor pattern from concentric rings, chain arcs, and a central eye glyph. Keep center contrast low enough for pink/violet/white bullets to remain highly visible; avoid placing bright decorative patterns directly behind projectiles.

## Custom items and rewards

All custom items currently use `lofiObj5:fe` placeholder art. Their names, slot types, descriptions, and associated boss drops are implemented; all visual descriptions below are commission direction.

| Item | Source / rarity signal | Recommended design |
| --- | --- | --- |
| Ominous Below Key | Dungeon access key | Black iron key with an eye-shaped bow, three small chain teeth, and a violet core. It should resemble a prison key corrupted by abyssal ritual. Medium-value key sprite; compact 16×16 or 24×24. |
| Mark of the Ferryman | 45% boss proof | A flat, wet ferry token/obol: dark silver rim, blank face, small cyan lantern notch. Common proof item, 16×16. |
| Ferryman’s Toll | very rare Ferryman accessory; speed-oriented | A dangling toll coin or miniature lantern charm on a broken chain. Desaturated brass, cyan flame, violet reflection. 16×16, strong circular silhouette. |
| Mark of the Warden | 45% boss proof | A broken iron shackle badge stamped with an eye/keyhole. Dark steel with amethyst crack. 16×16. |
| Chains of Veyra | very rare Veyra armor; defense-oriented | A heavy folded mantle of interlocked black chain links over a dark purple cloth underlayer. The item icon should read as armor, not a loose rope. 16×16; one bright steel edge and one violet rune highlight. |
| Mark of the Ominous One | 55% boss proof and guaranteed chest item | A cracked black eye medallion with a thin magenta pupil. 16×16, high contrast, clear circular silhouette. |
| Eye of the Ominous | very rare final-boss weapon; dexterity-oriented | A held/embedded eye relic in a black-gold claw setting. Bright violet iris, pale pupil, fractured crown rim. 16×16; should clearly read as a magic weapon. |
| Mantle of the Below | very rare final-boss robe; vitality-oriented | A wide void-black mantle with purple inner lining and crown/eye embroidery. Sharp pointed hem, as if it dissolves into smoke. 16×16, high silhouette separation from ordinary robes. |
| Ominous Completion Chest | final completion container | Short black reliquary chest with iron chain bands, an eye-lock, and violet light escaping seams. It should look ceremonial and deserved, not like a generic treasure box. 32×32 recommended. |

## Sprite-production priorities

### Priority 1 — mechanical readability

1. Ominous Soul Lantern
2. The Faceless Ferryman and Soul Barge Anchor
3. Veyra and Chain Anchor
4. The Ominous One, Ominous Seal, and Ritual Pillar
5. Portal, key, completion chest, and all six reward icons

These are the sprites the player must recognize to understand progression, invulnerability, and reward states.

### Priority 2 — enemy family readability

Create the drowned-route enemies as a family first (Pilgrim, Wraith, Hound, Attendant, Collector), then the prison family (Revenant, Judge, Iron Gaoler, First Gaoler, Last Gaoler), then the abyss family (Remnant, Eye, Devourer). Each family can share palette rules, but no two enemy roles should rely on the same silhouette.

### Recommended production scale

The game uses a low-resolution pixel-art view. Produce a clean master at **32×32 pixels for ordinary enemies and objectives**, **48×48 for the Ferryman and Veyra**, and **64×64 for the Ominous One**, then test the result at their logical game sizes. Provide 4-direction or 8-direction movement only where the engine’s existing visual conventions need it; static objectives need 2–4 purposeful idle/pulse frames. Avoid sub-pixel blur, painterly anti-aliasing, and overly thin filigree.

## Art direction rules

- **Contrast:** playable floor must be darker and lower contrast than enemies, objectives, player bullets, and hostile bullets. Never use the bright projectile palette as passive floor decoration.
- **Shape language:** drowned enemies are drooping, tapering, and water-worn; prison enemies are vertical, rectangular, and chained; abyss enemies are circular, radial, and asymmetrical around an eye.
- **Outlines:** use 1-pixel near-black outlines on light edges, selectively broken where violet light blooms. Bosses may use a 2-pixel outer silhouette at master size, but not a uniform cartoon outline.
- **Saturation:** reserve saturated violet/magenta for magic, objectives, and the Ominous One’s eye. Keep ordinary materials blue-black, charcoal, and desaturated steel.
- **Lighting:** cyan-violet underlight, not warm torchlight. Important props emit small pools of light and particles; background architecture mainly catches rim light.
- **Animation:** make attacks readable through anticipation and silhouette change. Lanterns brighten before firing, chains tighten before barrages, and eyes open before aimed shots. Avoid continuous idle noise that obscures timing.
- **Hierarchy:** boss > active objective > dangerous elite > normal enemy > background prop. The current shared placeholder makes these distinctions impossible; the new art must restore them.

## Final art bible

| Category | Direction |
| --- | --- |
| Mood | Cold, drowned, penitential, cosmic, ceremonial, oppressive; moments of violet revelation in near-total darkness. |
| Primary colors | Blue-black basalt, charcoal, deep indigo, muted steel. |
| Secondary colors | Desaturated cyan, pale spectral white, bruised purple, slate gray. |
| Accent colors | Saturated soul violet, ritual magenta, occasional crimson eye detail, restrained antique brass. |
| Recurring symbols | Blank mask, eye, chain link, toll token, lock, bar, broken seal, circular halo, downward-pointing spire. |
| Architecture | Drowned gothic ferryway → iron prison → nonhuman abyssal ritual geometry. |
| Environment | Wet black stone, shallow void-water, fog, chain shadows, sparse cold lights, no cheerful vegetation. |
| Enemy style | Strong role-first silhouettes; human remnants in the maze, institutional wardens in the prison, fragments/eyes/void creatures in the abyss. |
| Boss style | The Ferryman is a drowned threshold keeper; Veyra is a majestic but bound iron warden; the Ominous One is a crowned eye-sovereign occupying the room’s visual center. |
| Item style | Small black-metal reliquaries and proof tokens with readable cyan/violet cores; each carries one dungeon symbol and avoids generic fantasy gold. |

## Source basis

- `Server-src/common/resources/worlds/OminousBelow.jw` — world identity, size/difficulty, map reference.
- `Server-src/common/resources/worlds/OminousBelow.jm` — authored layout, object placement, floor/wall baseline.
- `Server-src/common/resources/xmls/EmbeddedData_OminousBelowCXML.dat` — custom object names, logical sizes, current placeholders, item descriptions, and rewards.
- `Server-src/wServer/logic/db/BehaviorDb.OminousBelow.cs` — enemy and boss behavior states, attacks, timing, and drops.
- `Server-src/wServer/realm/worlds/logic/OminousBelow.cs` — progression gates, wall removals, objective completion, and completion chest behavior.

