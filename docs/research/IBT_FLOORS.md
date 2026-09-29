# Floors and grandeur: how IBT grows a bank, and the plan for Grand Exhibit

Research date: 2026-09-29. Follows `IBT_LEVEL_STRUCTURE.md`. Store pages and the
PocketGamer / AppQuantum deconstructions are blocked from the build environment,
so this relies on search excerpts, the earlier screenshot study, and the owner's
brief ("first floor, second floor and grandeur, like IBT").

## What IBT does

- **A bank grows while you play it, not only between banks.** Later banks show
  distinct wings around a central hall with a staircase. Areas that aren't open
  yet are visibly there but **derelict** (grey, boxes, cobwebs, bare walls).
  Unlocking one renovates it into a saturated, furnished room. The unlock *is*
  the reward. (Screenshot study, `IBT_LEVEL_STRUCTURE.md` §3.)
- **Areas come in order and are shown ahead of time.** The next area and its
  requirement are visible, which gives a mid-term goal between station upgrades
  and "sell the bank".
- **Banks climb in grandeur.** They go from small-town branch to downtown bank to
  resort bank with underwater vaults to skyscraper megabank. Each step is a
  bigger, grander building with more rooms, and guides quote a ~2x income step
  per bank. ([GamingonPhone](https://gamingonphone.com/guides/idle-bank-tycoon-beginners-guide-and-tips/),
  [Level Winner](https://www.levelwinner.com/idle-bank-tycoon-money-empire-guide-tips-tricks-strategies/))
- **Separate areas off the main floor**: the event café (Franchise Frenzy), the
  vault wing, and Business Mode as its own screen.

## Grand Exhibit today

`data/venues.json` already models storeys: rooms carry `level` 0-3, and seven
museums have upper floors joined by stair "link" rooms (Chronos Spire and the
Infinite Museum have four levels). But every floor is open from the first
second. There's nothing to unlock, nothing to renovate, and the exterior
never changes.

## The plan

### 1. Wings, unlocked floor by floor
Each venue gets an ordered `wings` list (in `data/wings.json`, keyed by venue).
A wing is a group of rooms, usually a whole floor:

| Field | Meaning |
|---|---|
| `id`, `name` | e.g. `upper_hall`, "Hall of Giants (2nd floor)" |
| `floor` | 0 = ground, 1 = second floor, -1 = basement, 2+ higher |
| `rooms` | room ids from the venue theme that belong to it |
| `req_rep` | reputation needed before it can be opened |
| `cost` | cash to renovate, as a multiple of the venue's income curve (never absolute) |
| `income_mult` | permanent venue multiplier once renovated |
| `adds_items` | extra unit slots granted to a department (more exhibits, more desks) |

- The ground floor's core wing is always open. Every other wing starts
  **derelict**: the room is drawn grey with dust sheets, crates, scaffolding and a
  sign giving its requirement ("Opens at ★5").
- When requirements are met the sign turns into a **Renovate** button. Paying
  plays the renovation (scaffold drops, colour floods in, confetti), the
  multiplier applies, and visitors start using the room.
- The next locked wing always shows its requirement, so the player can see it
  coming.

### 2. Real floors in the 3D view
- Floors are stacked like a dollhouse. The camera frames one floor at a time. A
  floor selector (`B1 · G · 2F · 3F`) on the right edge, plus a vertical swipe,
  moves the camera up or down a storey. The floors above the one in view lift away
  (hidden), so nothing covers the floor you're working on.
- The overview (pinch out fully) shows the whole building with every floor, so
  you can see the museum is getting taller.

### 3. Grandeur tiers (the building gets grander)
A venue-wide tier from the share of wings renovated plus the star rating:

| Tier | Name | Exterior dressing | Bonus |
|---|---|---|---|
| I | Humble | plain facade | - |
| II | Restored | banners, planters, lamps | x1.10 |
| III | Grand | red carpet, gilded columns, fountain | x1.25 |
| IV | Magnificent | gold dome, statues, spotlights | x1.50 |
| V | Legendary | fireworks at night, banner with the museum's crest | x2.00 |

Each tier-up gets a full-screen moment, the same as IBT's bank-sold card.

### 4. Museum 1 (Whispering Pines) as the template
- **Ground floor**: today's plan. Welcome Desks, Nature Hall, Conservation,
  Members Lounge and the Lodge Foyer.
- **2F, Hall of Giants**: a new floor above the Nature Hall, reached by a
  staircase in the foyer. It holds the big hero exhibits (mammoth, whale
  skeleton), adds 2 gallery unit slots, and gives x1.5 income. Needs ★4.
- **B1, Fossil Lab**: a basement off the Conservation room where excavated
  finds are cleaned. It ties into the excavation mini game and boosts
  expedition rewards. Needs ★6.
- **Roof, Sky Terrace** (grandeur IV): a rooftop café with a telescope. It
  adds promotions slots.

Later museums reuse their existing `level` data as wings. For example, Chronos
Spire's four levels become four unlocks.
