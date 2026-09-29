# Passive circulation captures

Run `tools/circulation_shot.gd` with the same arguments as `tools/shot.gd`. It samples every five simulated seconds without changing visitor positions or forcing states.

Example: `godot --path . -s tools/circulation_shot.gd -- warm=65 venue=copper_kettle cash=1e12 levels=8 out=/tmp/tidewater.png`.

Always isolate saves with `XDG_DATA_HOME` and `GRAND_EXHIBIT_TEST_RUN=1`.

`cafe_browse_unique` counts unique actors observed in a café room while in browse state; it does not prove food purchases or seated service. `rest_unique` counts rest state, including travel toward seats. `garden_unique` is restricted to Grand River's garden walk. Sampling can miss brief visits. The final screenshot/census and clump report supplement these counters. Boosted economy runs establish movement behavior, not normal progression balance.


`tools/sunspire_circulation_shot.gd` adds passive Sunspire checks at five samples per simulated second. `stair_users` counts unique visitors observed inside the authored stair room. `sundial_arrivals` requires browse state, a target matching an authored sundial viewpoint, and a position within 0.25 tiles of it. These counters establish observed route use/arrival, not viewing duration, sustained throughput or monetization. They use the same isolated-save and screenshot arguments as the base harness.

`tools/movement_probe.gd` adds a passive arrival-stall diagnostic: one-second samples, `to_queue` state in both samples, displacement below0.08tiles for eight consecutive samples. It reports position, target and pending path once per affected actor. Zero reports is evidence only for that sample; it does not prove unlimited throughput or cover every visitor state.


`tools/elevation_probe.gd` checks consecutive simulation frames for a visitor moving less than0.25tiles while changing elevation by more than20pixels. It also counts unique visitors observed in each room. A report indicates a discontinuity worth investigating; the absence of reports only covers that run and threshold. It does not observe porters/staff, camera occlusion or finer foot sliding. Capture the same venue after route changes to distinguish visible crowding from actual elevation faults.
