# Grand Exhibit ↔ Idle Bank Tycoon parity audit

Date: 2026-07-29  
Scope: essential gameplay loop and supporting progression. Presentation parity is
tracked separately in `IBT_PARITY.md`. The target is mechanical familiarity, not
copied names, art, writing, layouts, or UI expression.

## Reference loop

Primary/reference sources:

- Idle Bank Tycoon official site:
  https://www.idlebanktycoon.com/
- Official gameplay/reputation documentation:
  https://kolibri-games.helpshift.com/hc/en/10-idle-bank-tycoon/faq/433-what-is-the-purple-star-at-the-bottom-of-the-bank-screen-what-is-reputation/
- Official manager assignment documentation:
  https://kolibri-games.helpshift.com/hc/en/10-idle-bank-tycoon/faq/454-how-do-i-assign-managers-how-do-i-use-managers/
- Official Business Mode documentation:
  https://kolibri-games.helpshift.com/hc/en/10-idle-bank-tycoon/faq/336-what-is-business-mode/
- Official Audit Madness documentation:
  https://kolibri-games.helpshift.com/hc/en/10-idle-bank-tycoon/faq/427-what-is-audit-madness/
- Official cash/statistics documentation:
  https://kolibri-games.helpshift.com/hc/en/10-idle-bank-tycoon/faq/421-how-can-i-get-more-in-game-cash/
- Official Vault-rate documentation:
  https://kolibri-games.helpshift.com/hc/en/10-idle-bank-tycoon/faq/436-does-leveling-up-the-vault-also-increase-how-much-money-is-deposited/

IBT's essential loop is:

1. Marketing attracts customers.
2. Customers queue at independently upgradeable service windows.
3. Service windows accumulate cash.
4. Transporters with upgradeable carrying capacity move that cash to a vault
   with an upgradeable deposit rate.
5. Main-hall/decor upgrades increase deposits and active tip rewards.
6. Upgrades grant Reputation, which attracts richer customers and gates features.
7. Three rolling missions drive object upgrades and bank-completion milestones.
8. Managers specialize in bank areas, improve productivity, and form teams for
   Business Mode/Audit Madness.
9. Business Mode converts cash into manager-upgrade currency and audit progress.
10. A completed bank is sold; cash and meta progression carry into a larger bank.
11. Offline earnings, active tips, and a persistent x2 boost create the return loop.

## Current parity matrix

| Loop component | Grand Exhibit implementation | Status |
|---|---|---|
| Marketing → service → transport flow | Promotions → Ticket → Archive; live rate model and actionable bottleneck indicator | MATCH |
| Individual functional objects | Department item arrays; independent station levels and item contribution | MATCH |
| Per-window cash | Independent persisted cashier piles | MATCH |
| Active station collection | Cash chips collect one station; per-station cooldown prevents bypassing transport indefinitely | MATCH, original safeguard |
| Physical transporters | Visible porters, up to three, collecting cashier stacks and delivering to Archive | MATCH |
| Back-of-house porter route | Authored service corridor behind tellers in every venue | MATCH |
| Vault deposit + cart capacity | Archive speed controls deposit rate; independently levelled porter/cart items contribute carrying capacity | MATCH |
| Main Hall economic role | Gallery raises visitor value; decor/seating affects rating and tips | MATCH with museum adaptation |
| Decor visual transformation | Purchased pieces immediately appear on the floor | MATCH |
| Decor → earnings/tips | Decor raises rating, visitor value, bag chance, and bag value; seating raises rest score | MATCH+, composite rating is original |
| Visitor satisfaction feedback | Star breakdown, reasons, dissatisfied walkaways, angry facial state | MATCH+ |
| Reputation | Every upgrade grants XP; explicit REP level/progress; feature gates | MATCH |
| Rolling missions | Three active quests; item, department, earnings, serving, manager, and decor targets | MATCH |
| Bank/venue completion | Authored milestone chain plus capped core-flow build, READY state, one-way venue transition | MATCH |
| Cash across transitions | Retained; pending floor cash swept before move | MATCH |
| Offline loop | Capped offline calculation and Welcome Back multiplier choice | MATCH |
| Persistent x2 boost | World-view BoostDock | MATCH |
| Manager collection | Rarity, cards, briefcases, duplicates, assignment specialties | MATCH |
| Manager assignment slots | One to three specialist posts per department, unlocked with Reputation | MATCH |
| Manager long-tail depth | Ten data-driven ranks with level caps rising from 20 to 300 | MATCH |
| Manager stat roles | Productivity drives department output; Audit Efficiency drives inspection strength; both are labelled in UI | MATCH |
| Business Mode analogue | Expedition cash investment, idle Insight storage, match-3 boss | MATCH |
| Audit Madness analogue | Inspection event with manager team and match-3 | MATCH |
| Limited-time event cadence | Day-gated timed event | MATCH |
| Venue runway | Twelve authored venue plans with track caps rising 15 -> 100, structural-variation tests, and scripted completion targets | MATCH, see note |
| Statistics guidance | Unified flow dashboard shows arrival, service, transport, physical limit, income, satisfaction, and an actionable department shortcut | MATCH |
| Active tips | Satisfaction-scaled money bags distributed through the venue | MATCH+, museum adaptation |
| Vault visual fill | Cash pile responds to lifetime earnings; porter deposits trigger a contained scale pulse and coin glint | MATCH |

## Engineering priorities

### P0 — closes the remaining core-loop discrepancy

1. **DONE:** Build a unified Statistics sheet showing arrival, service, transport, vault
   fill, value per visitor, and the next actionable improvement. Never mark a
   capped department as an upgrade recommendation.
2. **DONE:** Author and test a back-of-house porter corridor for every venue layout.

### P1 — restores IBT's medium/long progression depth

3. **DONE:** Split manager presentation into Productivity and Audit Efficiency.
4. **DONE:** Expand manager promotions to a data-driven rank/level-cap ladder.
5. **DONE:** Add Reputation-gated assignment slots where the manager economy supports them.
6. **DONE:** Validate each venue's quest duration, station caps, costs, and completion time
   against explicit session targets.

### P2 — retention/content parity

7. **DONE for 1-6 and 12; OPEN for 7-11.** Layouts are structurally distinct across
   all twelve (test_variation holds unique massing per venue), but venues 7-11
   still share the generic `late_art` exhibit set — the same seven pieces at the
   same fractional offsets, recoloured. Distinct PLAN, indistinct CONTENT.
8. **DONE:** Add venue-specific decor anchors so pieces transform appropriate rooms instead
   of using only shared edge slots.
9. **DONE:** Add manager aura/workstation feedback and stronger vault fill animation.
10. **DONE:** Run first-session, first-day, and first-week scripted balance
    simulations. The conservative no-boost harness completes Whispering Pines
    in 30:23, reaches Copper Kettle at 2:16, Grand River at 4:57, Sunspire at
    9:11, Cloudrest at 1d 5:47, and then opens Aurora as the week-one long tail.

## Roster note (2026-07-30)

This audit was written against a six-venue roster and the game now ships twelve.
Every loop row above was re-checked and still holds; the runway row is the only
one whose numbers changed. Two venues are NOT shippable as currently framed —
chronos_spire's lobby is 88% off-canvas and empyrean_palace's is 100% at the zoom
the renderer actually uses — and both fail loudly in the generator rather than
silently. Presentation status for all twelve lives in `IBT_PARITY.md`.

## Guardrails

- Preserve the museum setting, satisfaction system, reactive traffic, distributed
  tips, dedicated exits, and per-cashier collection cooldown.
- Shared behavior belongs in Economy, Character, DecorSystem, and VenueFloor.
  Venue data should author only geometry, theming, and balance values.
- Do not copy IBT art, writing, names, layouts, or branded UI.
- A red bottleneck marker must always indicate an action the player can still take.
