# Grand Exhibit vs Idle Bank Tycoon: parity scorecard

Updated 2026-09-29. Status: ✅ at parity or better · 🟡 partial · ⬜ not yet.
Sources on IBT: `docs/research/IBT_LEVEL_STRUCTURE.md`, `docs/research/IBT_FLOORS.md`.

## Core loop

| IBT | Grand Exhibit | Status |
|---|---|---|
| Bank with departments (hall, tellers, marketing, vault), each with stations that level up | Museum with Welcome Desks, Galleries, Promotions and Conservation; every unit levels (items) | ✅ |
| Clients walk in, queue, get served; money piles up at stations | 3D visitors arrive from the street, buy tickets, tour exhibits, ride lifts; coin chips on counters | ✅ |
| Tap to collect, coins fly into the counter | Station chips, dig-site finds; coins arc into the HUD counter, which bounces | ✅ |
| Bottleneck guidance | Statistics sheet + red "limits income" badge on the department sheet | ✅ |
| Offline earnings, welcome-back ×2 | Welcome Back popup (ad ×, gem ×) | ✅ |
| Quests (3 at a time) + milestone bar | Goals bar, milestones with gems and loot boxes | ✅ |
| Daily login rewards | Daily Gifts: a seven-day calendar (gems, minutes of income, dig energy, x2 time, a Specialist Case on day 7). A missed day never resets the week | ✅ |
| Reputation level unlocks features | Reputation: Managers (Rep 3), Dig Site (Rep 2), Boss Expedition (Rep 7) | ✅ |

## Levels and growth

| IBT | Grand Exhibit | Status |
|---|---|---|
| A ladder of banks, each bigger and grander | 12 museums, from a small-town hall to the Infinite Museum, each a distinct 3D building | ✅ |
| Banks grow mid-level: derelict areas renovated in order, next one shown ahead | Floors and wings (2F, 3F, …, Gilded Facade) open by goal milestones. They sit grey under dust sheets until renovated, then colour floods in. Glass lifts take visitors up | ✅ |
| Grandeur climbs with the bank | Grandeur Humble → Legendary: banners, red carpet and spotlights, gold statues, a gold dome, fireworks | ✅ (beyond IBT) |
| Decor is levelable department items | Placed decor levels 1–10 (+income, +decor points, +reputation), priced in each museum's economy | ✅ |
| Decor themed per bank | Each museum stocks its own four-piece themed set, unlocked by its milestones and shown locked in advance, plus the classic catalogue | ✅ |
| New client types per reputation level | Visitor Guide: 8 visitor types unlocked by reputation (locals, little explorers, students, tourists, critics, then VIP collectors, celebrities and royal patrons), each dressed as a toy in the museum and shown live in the guide. VIPs walk on a gold ring and carry a tappable tip bubble (30–90 s of income, on a cooldown) | ✅ (beyond IBT) |

## Meta and events

| IBT | Grand Exhibit | Status |
|---|---|---|
| Managers (cards, levels, assignment) | Managers: cards, levels, ranks, posts per department | ✅ |
| Business Mode (match-3 boss fights) | Inspection (match-3) on the Event tab; Boss Expedition inside the Dig Site | ✅ |
| (none) | **Dig Site**: excavation mini game themed per museum (fossils, shipwreck, tomb, ice cave…). Pick vs brush, cracks, energy; artifacts join the museum's collection and raise its income | ✅ (beyond IBT) |
| Franchise Frenzy event with its own café area and currency | **Pop-Up Café**: a 3-day event every 5 days with its own 3D toy diorama, themed per museum (Dino Diner, Harbour Chowder Hut, Oasis Tea Tent, Royal Patisserie…). Café coins (earned offline too) upgrade four stations; every level is a star on a 10-step reward track (gems, manager cases). A café stand on every museum's plaza opens it | ✅ |
| Store: gem packs, bundles, boosts, passes | Store with offers, gems, resources, passes (stub billing) | ✅ (billing SDK to wire) |
| Rewarded ads (×2 income, free gems, instant cash) | Boost dock + ad refills (debug ad service; AdMob to wire) | ✅ (SDK to wire) |

## Presentation

| IBT | Grand Exhibit | Status |
|---|---|---|
| Bright 3D-look buildings | Real-time 3D toy-diorama museums (Link's Awakening-style glossy toys), tilt-shift, saturated palettes per museum | ✅ |
| Big showpiece items | Hero exhibits (T. rex, mammoth, blue whale, sarcophagus, reef tanks, orreries…) grow and gain light beams, gold rings and sparkles as the gallery levels | ✅ |
| Light, chunky UI | Toy chrome: cream cards, chunky borders, green actions, on every screen including the Store | ✅ |
| Onboarding with a pointing hand | First-run walkthrough: collect → upgrade → open a hall → floors → Dig Site; replayable from Settings | ✅ |
| Settings | Music, sound, graphics (Auto / High / Low), fullscreen on PC, replay walkthrough | ✅ |

## Platforms

| Target | Status |
|---|---|
| Android | ✅ preset + build script (billing/ads SDKs to wire). The game pack is about 45 MB: exports leave out the 2D floor's sprite sheets |
| iOS | 🟡 preset; needs a Mac with Xcode, StoreKit/Game Center plugins |
| Steam (Win/Linux/Deck/macOS) | 🟡 presets, window/letterbox, achievements layer; install GodotSteam, create the app |
| Epic | 🟡 preset + EOS seam |
| Microsoft Store | 🟡 Windows build + MSIX packaging steps |

See `docs/PLATFORMS.md`.

## Open items (next)

1. Wire the real SDKs: Play Billing, AdMob, StoreKit, GodotSteam, EOS.
2. Profile on a low-end phone. The graphics switch is in (Low drops shadows,
   MSAA, glow and tilt-shift and caps the crowd; Auto falls back to Low when
   the museum averages under 40 fps), but it hasn't been measured on hardware.
