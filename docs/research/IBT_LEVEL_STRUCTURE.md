# Idle Bank Tycoon: how its levels are structured, and what Grand Exhibit gets wrong

Research date: 2026-09-28. Sources: Play/App Store listings and version history, Kolibri help center, PocketGamer.biz deconstruction, and player guides (links at the bottom). Items marked *(inferred)* come from store screenshots rather than a written source.

## 1. A bank is a set of departments, and each department is a set of upgradeable items

Every bank has the same four departments. Each one holds several named **items**, and each item levels up on its own:

| Department | Job | Items named in guides |
|---|---|---|
| Main Hall | Receives clients; seats fill with money bags over time | Seats, Client Support, **Decorations**, Lounge, Electronics, Cafe |
| Service Area | Tellers process deposits | Office Equipment, Fish Tank |
| Marketing Office | Agents call clients in | Resting Area, Office Equipment, Kitchenette |
| Vault | Stores cash; porters haul it with carts | Cash Carts, Security Equipment, Monitors, Statue |

**Decor isn't a shop.** Fish tanks, statues, lounges, cafes and kitchenettes are items *inside* a department. They level up like any station. Each upgrade adds income and **reputation stars**. So decor progression *is* level progression, and there's no separate list to buy from.

Guides note that "when you unlock a new item, the cost of upgrading it 20 levels higher will certainly be less" than pushing an old one. New items keep appearing inside each department as you progress, which constantly refreshes what's worth buying.

## 2. Reputation is the player's level, and it gates content

- Every upgrade earns reputation points. The purple star shows the level and "the progress of the decoration bonus too".
- Each reputation level unlocks **richer client types**, shown in advance with the level they arrive at. It also gives hard currency or extra clients.
- Managers unlock at reputation 6; Business Mode (match-3 bosses) at reputation 7.
- Milestones come in three layers: quests (3 at a time), an on-screen progress bar, and a bank-completion bar in the menu. At 100% the bank is "sold" and you move on. You can't go back, but **cash carries over**.

## 3. Later banks have more rooms, not just bigger ones

- Banks are named stages: small town → "Big Town, Bigger Bank" (bank 3) → "Making Waves" (bank 6) → … → "Argent Atoll", a luxury Maldives bank with **underwater vaults** → a skyscraper megabank. The progression map was rebuilt in v1.95 so this path reads "from a small-town branch to a skyscraper megabank".
- *(inferred from the "Be an idle bank tycoon" screenshot)* A late bank is a cluster of distinct, differently colored **wings** around a curved central hall with a staircase: orange marketing office, blue staff room, a purple lounge, a large multi-room vault wing lined with money shelves, and a street, bus stop and lawn outside. Each wing reads as its own place.
- *(inferred from the "Build your bank empire" screenshot)* Rooms start **derelict**: grey, cobwebs, boxes, bare walls. They're renovated into saturated, furnished rooms as you unlock them. The unlock *is* the visual reward.
- Guides confirm later banks "take more time to complete since they're bigger and rooms have more items to upgrade".

## 4. Separate areas outside the main bank

- **Franchise Frenzy** is an event with its own café area and its own decorations, bought with a separate currency (Franchise Coins, visually refreshed in v1.88). It's an area that isn't the bank floor.
- **Business Mode** is a separate screen with match-3 boss fights.

## 5. Grand Exhibit's decor system today, and why it's broken

Checked in `scripts/meta/decor_system.gd`, `data/decor.json` and `data/venues.json`:

1. **One global shop of 24 pieces**, the same in every museum (the aquarium and the space museum both sell the Oak Bench). Pieces go into generic slots (6 in M1 up to 20 in M12).
2. **Cash prices are absolute and never scale.** They run from $500 to $15M in every museum, while income reaches trillions in M1 alone. After the first minutes the whole cash catalog is effectively free, so buying decor stops being a decision.
3. **Nothing gates decor behind progression.** There are no reputation, level or venue requirements in the data, and the shop screen shows none.
4. **Decor doesn't level up.** A piece is bought once and done. Only its flat `income_mult` counts, so it never feeds reputation the way IBT's items do.
5. The file comments claim each museum "stocks its own shelves at its own prices", but the code charges the same flat `cost_cash_m`/`cost_cash_e` everywhere.

## 6. What to do about it

- **Make decor department items.** Each room type (lobby, gallery, hall, café, archive/vault, garden) gets 2–4 named decor items that are *themed per museum* (aquarium: jellyfish column and coral arch; Chronos: pendulum and orrery). They unlock in sequence as the department levels up, and each one is **levelable** with the same cost curve as the stations. Every decor level grants reputation.
- **Scale prices per museum** from the venue's own income curve, not absolute values.
- **Tie reveals to reputation**: every reputation level unlocks a named reward (new visitor type, new decor item, new wing), shown in advance like IBT's client cards.
- **Make later museums structurally different**: extra wings and separate areas (a garden court, a rooftop observatory, an underground archive, an aquarium tunnel) that unlock mid-museum, each with its own look and item set. Rooms start derelict and are renovated when unlocked.
- Keep the cross-museum **set collection** (`decor_sets`) as a meta layer on top, since IBT doesn't have it.

## Sources
- [Idle Bank Tycoon on the App Store (description, version history)](https://apps.apple.com/us/app/idle-bank-tycoon-money-game/id1645281275)
- [Idle Bank Tycoon on Google Play (screenshots)](https://play.google.com/store/apps/details?id=com.luckyskeletonstudios.idlebanktycoon&hl=en_US)
- [PocketGamer.biz: Deconstructing Idle Bank Tycoon](https://www.pocketgamer.biz/game-analysis-deconstructing-idle-bank-tycoon-by-kolibri-games/)
- [Kolibri help center: Gameplay basics](https://kolibri-games.helpshift.com/hc/en/10-idle-bank-tycoon/section/153-gameplay-basics-core-mechanics/?l=en)
- [FatWallet Refugee game guide](https://fatwalletrefugee.com/2024/02/27/idle-bank-tycoon/)
- [Level Winner guide](https://www.levelwinner.com/idle-bank-tycoon-money-empire-guide-tips-tricks-strategies/)
- [GamingonPhone beginner's guide](https://gamingonphone.com/guides/idle-bank-tycoon-beginners-guide-and-tips/)
