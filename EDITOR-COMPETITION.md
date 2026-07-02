# OpenAPI Editor / IDE Competition — Research

*June 23, 2026. Question: is there room for a Mac-native, repair-first, privacy-first OpenAPI spec IDE, and what could it charge?*

---

## TL;DR

The **native-Mac visual-editor niche is almost entirely open** — the two big free visual desktop editors (Stoplight Studio, Apicurio Studio) are now dead/frozen, and only one tiny indie (OhAPI Designer, ~$24, unproven) occupies the native-Swift space. **But** the *editing/preview layer itself is free and crowded* — 42Crunch's free VS Code extension alone has ~1.5M installs. So a paid Mac IDE can't win as "a nicer OpenAPI editor." It has to win on the things that are **thin or missing everywhere**: in-the-loop auto-**repair**, **scaffolding from a library of real-world specs** (a genuine gap — nobody does this), native speed/privacy, and MCP-readiness.

---

## What died (the opening)

- **Stoplight Studio (standalone desktop):** effectively abandoned. No releases since SmartBear's 2023 acquisition; SmartBear says desktop support "is not currently part of Stoplight's plans" and steers users to Studio Web + the paid API Hub platform. *(stoplight.io/pricing; community.smartbear.com)*
- **Apicurio Studio (Red Hat):** **discontinued** — repo archived Oct 23, 2025, design folded into Apicurio Registry. *(apicur.io/blog/2025/10/23/studio-fully-deprecated)*

Two of the best-known free visual OpenAPI design tools are gone in the last ~2 years. That's the gap.

## What's alive (the competition)

**Cross-platform (Electron/web — none native Mac):**
- **Apidog / Apifox** — strongest all-in-one (design + mock + test + docs), real visual designer with reusable components; Mac/Win/Linux desktop but Electron-style. Free up to 4 users; ~$12–24/user/mo; Enterprise ~$324/user/yr. Rising fast as the Postman/Stoplight alternative. *(apidog.com/pricing)*
- **Insomnia (Kong)** — API Design module (Spectral lint, preview), design on free tier; $0 / $12 / $45 per user/mo. Electron. *(insomnia.rest/pricing)*
- **Postman** — Spec Hub / API Builder (form/code-driven). **Free plan drops to 1 user March 1, 2026**, pushing teams to paid. Electron. *(blog.postman.com)*
- **SwaggerHub → "API Hub" (SmartBear)** — Swagger Editor is free code-based; hosted platform paid (~$75–90/user/mo, *unverified, JS-rendered page*).

**VS Code extensions — the real default (most devs edit specs here), all free at the editor layer:**

| Extension | Installs (2026-06-23) | Notes |
|---|---|---|
| 42Crunch OpenAPI Editor | ~1,526,000 | Free editor + preview + **quick-fixes**; paid enterprise security Audit/Scan |
| Swagger Viewer | ~970,000 | Preview only |
| Redocly OpenAPI | ~81,000 | Lint + preview + partial visual forms + "Add template" |
| Spectral | ~61,000 | Pure linter |
| SwaggerHub (SmartBear) | ~14,000 | Ties to paid SwaggerHub |
| **APIMatic (auto-fix)** | ~5,100 | One-click **auto-fix/refactor**, 542 rules — cloud/account-gated |

*Takeaway:* free preview/edit tools dominate volume; **auto-fix and deep validation are thin (APIMatic ~5K) and all funnel to a paid cloud/enterprise backend.** Nobody scaffolds from a library of popular real-world specs.

## The one native-Mac player

- **OhAPI Designer (CoxOne)** — native Swift/AppKit ("no Electron"), OpenAPI 3.0/3.1, inline validation, `$ref` nav, snippet templates, operations panel. **~$24 one-time**, Mac App Store + direct, updated Apr 2026 — but **negligible traction** (≈3 MacUpdate downloads, near-zero reviews). Credible and active, but unproven. *(coxone.com/en/products/ohapi-designer.html)*

So the native niche is open — though its emptiness may partly reflect that most developers are content editing YAML in free VS Code extensions. Treat "open niche" as opportunity *and* as a demand warning.

## Pricing anchors for a paid Mac dev tool (verified)

Indie Mac dev tools cluster in two models:
- **Perpetual ~$89–129** with 1 year of updates, then optional ~$59–79 renewal — Proxyman ($89–99), TablePlus ($99–129).
- **Annual subscription ~$69–99/yr** — Tower ($69–149/yr), Kaleidoscope (~$96/yr), Dash (moved to ~$15–20/yr).

Most serious Mac dev tools **sell direct (off the App Store)** via Stripe/Paddle/Lemon Squeezy to dodge Apple's cut (~3–8% processor vs Apple's 30%, or **15% under the App Store Small Business Program** for <$1M proceeds). *(developer.apple.com/app-store/small-business-program; vendor pricing pages, 2026-06-23)*

**Anchor for an OpenAPI IDE: ~$99 one-time (1-yr updates) or ~$79/yr, sold direct.**

---

## Verdict & wedge

1. **Don't sell "an OpenAPI editor."** The editing layer is free and crowded (42Crunch 1.5M installs). You'll lose on features-per-dollar against free.
2. **Sell what's missing everywhere:**
   - **Repair-in-the-loop** — your engine fixes as you author, not a separate lint step. Auto-fix is thin (APIMatic ~5K) and cloud-gated; yours is local.
   - **Scaffold from a library of popular real-world specs** (Stripe, GitHub, etc.) + compose reusable components — *no tool does this*; it's your most unique idea.
   - **Native Mac speed + offline/privacy** — everyone real is Electron/web; nothing is uploaded.
   - **MCP / AI-agent readiness** as a first-class check — the freshest angle.
3. **Sequence it:** ship the **free WASM web app (check → fix → report)** first — it's the low-cost, clearly-gapped, demand-validating move and the funnel. Build the **Mac IDE second**, only if the authoring/compose use case shows real pull. The web app de-risks the expensive native bet.
4. **Price** the Mac app ~$99 one-time or ~$79/yr, sold direct (Lemon Squeezy), keeping recurring cost near the domain.

**Caveats:** SwaggerHub/API Hub and RocketSim exact prices unverified (JS-rendered pages); OhAPI traction unverified; install counts are cumulative, not active users.
