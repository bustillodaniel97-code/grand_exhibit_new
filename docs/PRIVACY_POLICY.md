# Privacy Policy — Grand Exhibit

**Last updated: 29 July 2026**

This policy explains what Grand Exhibit collects, why, and what you can do about
it. It is written to be accurate against what the app actually does — every
claim below corresponds to code in this repository, and the "Where this lives"
notes point at it.

> **Before publishing:** replace `[DEVELOPER NAME]`, `[SUPPORT EMAIL]` and
> `[PUBLISHED URL]`, then host this at a public URL. Google Play requires the
> policy to be reachable without logging in, and the same URL must be entered in
> the Play Console listing *and* linked from inside the app.

---

## Who we are

Grand Exhibit is published by **[DEVELOPER NAME]**.
Contact: **[SUPPORT EMAIL]**

## What we collect

**We do not ask you for personal information.** There is no account, no login,
no email capture, and no social sign-in. We do not collect your name, address,
phone number, contacts, photos, files, precise location, or microphone or camera
input.

The app does involve three kinds of data:

### 1. Your game progress — stored on your device only

Cash, museum progression, upgrades, decor, managers, settings and purchase
entitlements are saved to your device's private app storage. This never leaves
your device and we cannot read it. Uninstalling the app deletes it.

*Where this lives: `autoload/save_system.gd`. Android Auto Backup is
deliberately disabled, so this save is not copied to your Google Drive.*

### 2. Advertising identifier — collected by Google AdMob

Rewarded and interstitial ads are served by **Google AdMob**. To do that, AdMob
receives your device's advertising ID (AAID) along with standard technical
information such as device model, OS version, coarse region and IP address.
Google uses this to select and measure ads.

We do not receive, store or sell that data. Google's handling of it is governed
by their own policy:
<https://policies.google.com/technologies/partner-sites>

**In the EEA, UK and Switzerland**, we ask for your consent before any
personalised advertising, using Google's User Messaging Platform. If you decline,
ads still appear but are **non-personalised**.

*Where this lives: `scripts/monetization/consent.gd`, `autoload/ad_service.gd`.*

### 3. Anonymous gameplay diagnostics

We record anonymous events — a museum completed, an upgrade bought, an ad
finished, an error — to find bugs and balance the game. These carry no
identifier that points to you as a person.

**Nothing is recorded until you have answered the privacy prompt**, and if you
decline, analytics stay off.

*Where this lives: `autoload/analytics.gd`; it writes nothing before
`Consent.resolve()` has run.*

## Purchases

In-app purchases are processed by **Google Play Billing**. We never see or store
your card details. We receive only a purchase token and order id, used to deliver
what you bought and to make sure you are not charged or granted twice.

*Where this lives: `scripts/monetization/play_billing.gd`.*

## Your choices

- **Change your privacy choice at any time** — Store → *Privacy choices*, inside
  the app. This re-opens the consent form.
- **Reset your advertising ID or opt out of ad personalisation** — Android
  Settings → Privacy → Ads.
- **Delete everything we hold about you** — uninstall the app. Your save is local,
  so removing the app removes it. For anything held by Google on our behalf,
  email **[SUPPORT EMAIL]** and we will action the request within 30 days.

## Children

Grand Exhibit is **not directed at children under 13** and we do not knowingly
collect data from them. If the app is ever published under a families programme,
a single configuration flag forces non-personalised advertising for every user
regardless of consent state.

*Where this lives: `policy.child_directed` in `data/store_iap.json`, read by
`scripts/monetization/consent.gd`.*

## Data retention and security

Your save stays on your device for as long as the app is installed. Diagnostic
events are retained no longer than 14 months. All network traffic uses HTTPS.

## Third parties

| Service | Purpose | Their policy |
|---|---|---|
| Google AdMob | Serving and measuring ads | <https://policies.google.com/technologies/partner-sites> |
| Google Play Billing | Processing purchases | <https://policies.google.com/privacy> |
| Google User Messaging Platform | Collecting consent in the EEA/UK | <https://policies.google.com/privacy> |

## Changes

If this policy changes materially we will update the date above and surface a
notice in the app before the change takes effect.

## Contact

Questions or data requests: **[SUPPORT EMAIL]**
