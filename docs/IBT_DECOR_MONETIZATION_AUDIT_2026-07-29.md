# IBT decor and monetization behavior audit

Date: 2026-07-29

This is a clean-room product-behavior audit. It records observable UI, package
metadata, and configuration/type identifiers. It does not copy proprietary code,
assets, layouts, text, or branding.

## Evidence inspected

- Public Idle Bank Tycoon help pages and storefront-facing behavior.
- Version 1.95.0 installed from Google Play on an authorized test phone.
- Android manifest, bundled SDK inventory, and non-source metadata strings.
- Live bank and Vault Room screens, without purchases or save modification.

## Decor model

Metadata identifiers include `UpgradeDecoration`, `CategoryDecorationMap`,
`DecorationPayPerSec`, `DeskDecorationSprites`,
`CustomerDecorationInteractions`, and free/occupied customer-decoration
selection. Together with the visible upgrade UI, this supports the following
behavioral interpretation:

1. Decorations belong to functional areas rather than a detached collection.
2. Individual decorations can be upgraded.
3. They contribute a direct per-second economic value.
4. Their visual state changes with upgrades.
5. Customers can visibly interact with available decoration points.
6. Area expansion and decoration progression are related.

Grand Exhibit should adapt those principles, not reproduce IBT's expression:
purchases appear in their relevant room immediately, provide clearly disclosed
income/satisfaction effects, gain visible upgrade tiers, and create optional
visitor interactions that never block service or exit paths.

## Monetization model

The installed package includes Google Play Billing plus Google Mobile Ads,
AppLovin/AppHub, Digital Turbine, Meta Audience Network, AppsFlyer, Firebase
Analytics, and Crashlytics integrations. Observable/configuration evidence shows:

- optional rewarded-video placements and ad-watch store rewards;
- ad/boost tickets;
- timed and permanent no-ad/boost entitlements;
- a persistent x2 boost;
- daily deals and a free shop claim;
- rotating and endless timed offers;
- piggy-bank and season-pass style products;
- first-purchase packages and purchase limits;
- blended ad and in-app-purchase revenue measurement.

This is a hybrid rewarded-ad and IAP economy, not an ads-only economy.

## Independent implementation priorities

1. Keep rewarded ads optional and placement-specific.
2. Add a transparent earnable ticket alternative to ad watching.
3. Keep permanent/timed convenience entitlements explicit and restorable.
4. Drive offers from validated local data with sane defaults; remote values may
   adjust presentation and pricing but must not control core save integrity.
5. Add purchase limits, consent, restore-purchase handling, and age/privacy gates
   before enabling real-money products.
6. Never make decor visibility, basic progression, or congestion relief depend on
   an advertisement.

## Current-save finding

The current Grand Exhibit save has an empty `decor` dictionary for every venue,
so the floor correctly has no purchased decor to instantiate. Older analytics
records show past purchases of the Heritage set, which indicates a later save
reset/replacement rather than a draw failure. The game should not silently
reconstruct signed save state from analytics; a future migration/recovery tool
can offer an explicit, auditable restoration path.
