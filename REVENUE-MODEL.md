# OpenAPIDoctor: Revenue Model

*June 23, 2026. How much could an OpenAPI editor + validator (plus a visual, component-based builder and "fork a popular spec" import) realistically make? Bottom-up model with stated assumptions and cited inputs. Numbers are deliberately conservative; dev tools are one of the lowest-converting freemium segments.*

---

## TL;DR

Realistic outcomes for a solo-built, bootstrapped product, by roughly year 2:

| Scenario | Annual revenue | What it takes |
|---|---|---|
| **Conservative** | **< $5k/yr** | A good tool, little distribution. The default outcome. |
| **Base** | **$30k–$60k/yr** | Real organic traction, SEO, an active free web tool, a paid Mac app + small team tier. |
| **Optimistic** | **$150k–$300k/yr** | Word-of-mouth hit, the MCP angle lands, featured/shared widely, sustained marketing. |

**The binding constraint is distribution, not price or conversion.** A solo maker's bottleneck is how many of the right people ever find the tool. The ceiling sanity-check: **Stainless**, an a16z-backed API tool with OpenAI and Anthropic as paying customers, was only at **~$1M ARR after ~2 years**. A bootstrapped solo OpenAPI desktop app should model *well* below that.

---

## The funnel (this is what decides the number)

Revenue = **reach → engaged users → conversion → price**. For a solo maker the first arrow is the hard one.

**Cited benchmarks used:**
- Free-to-paid conversion for **developer tools: 2–6%** (daily.dev, 2026), with freemium median **3.7%** (First Page Sage, 2026). Dev tools skew to the *low* end (devs self-serve and resist paying). → I use **1% / 2.5% / 5%**.
- Visitor → free use: **~12–15%** (First Page Sage). → I use **10–15%**.
- Apply conversion to **engaged users, not raw installs/visits**: install counts massively overstate (42Crunch's free OpenAPI extension has ~1.5M installs; almost none would pay).
- Price anchor: comparable indie Mac dev tools = **~$99 one-time (1-yr updates)** or **~$69–99/yr** (Proxyman, TablePlus, Tower). Sold direct to avoid Apple's 30% / use the 15% Small Business Program.

### Scenario math (steady-state ~year 2)

**Conservative**: niche, mostly organic, slow:
- ~2,000 site visitors/mo → ~300 engaged/mo → ~3,600 engaged/yr
- × 1% conversion = ~36 paid/yr × ~$80 avg ≈ **~$3k/yr** (+ a handful of team subs). **< $5k.**

**Base**: 2 years of SEO + community + a genuinely useful free web tool:
- ~10,000 visitors/mo → ~1,500 engaged/mo → ~18,000 engaged/yr
- × 2.5% = ~450 paid/yr × ~$90 avg ≈ **~$40k**
- + small team/CI tier: ~30 orgs × $19/mo ≈ **~$7k**
- ≈ **$45k–$50k/yr.**

**Optimistic**: word-of-mouth hit, MCP-readiness angle catches the AI wave, featured widely:
- ~40,000 visitors/mo → ~6,000 engaged/mo → ~72,000 engaged/yr
- × 4–5% = ~3,000 paid/yr × ~$90 avg ≈ **~$270k**
- + ~150 orgs × $19/mo ≈ **~$34k**
- ≈ **~$300k/yr.**

These bands match the independent comparable evidence: a strong solo Mac developer reached ~$300k/yr (multi-product, Indie Hackers); Gumroad's *average* software product earns ~$60k lifetime; niche paid dev desktop tools realistically land **$20k–$300k/yr**.

---

## Pricing structure that fits the model

- **Free:** the WASM web tool (check + see diagnoses). Funnel, not revenue.
- **Pro Mac app:** **$99 one-time with 1 year of updates**, then ~$59 renewal, *or* ~$79/yr. Sold direct via Lemon Squeezy/Paddle (merchant-of-record handles VAT; ~5–8% fee, no monthly).
- **Team / CI tier:** ~$19/org/mo, the only segment with reliable willingness-to-pay (budget lives at the team level, not the individual).
- **Paid report/document generation:** gate the shareable diagnosis/fix report behind Pro; it's your clearest differentiator and the thing nobody gives away.

---

## Demand check on the specific features you named

The research is honestly mixed. Two pillars are strong, two are risky:

**Strong (build these):**
- **"Start from a popular spec / fork it"**: the strongest pillar. APIs.guru has ~2,500 specs / ~108k endpoints (free, REST-accessible); Postman reports forking public specs is a large, growing workflow. Real, validated demand.
- **Webhook + auth scaffolding**: legitimate pain. OpenAPI 3.1 added `webhooks`; 50% of teams use webhooks; tooling support lags; auth wiring is error-prone. A credible feature wedge.
- **Repair in the editing loop**: auto-fix is the thinnest, least-served part of the whole market; your local engine is the differentiator.

**Risky (don't bet the product on these):**
- **A Delphi/VB-style drag-and-drop visual builder**: the core developer audience increasingly *prefers* text + Git and actively distrusts tools that own a proprietary internal format with no clean round-trip back to OpenAPI. Postman's visual API Builder was *deprecated*; several 2020-era GUI editors are dormant; survivors (Stoplight) got acquired rather than winning solo. Offer visual editing *alongside* round-trippable text, never instead of it.
- **A reusable-component marketplace**: no observed precedent and no demonstrated demand. Component reuse is already solved org-internally with `$ref` + Git. This is the most speculative idea; treat it as a maybe-later, not a v1 pillar.

Also sobering: an industry newsletter literally ran "All Devtools Die" in June 2026; this category has a high death/consolidation rate. Plan for a lean, low-cost build you can sustain solo, not a venture-scale bet.

---

## Honest bottom line

- **Most likely (default): a few thousand $/year.** A good tool that few people find.
- **A realistic good outcome with real effort on distribution: ~$30k–$60k/year**: meaningful side income, not a salary.
- **Upside if it catches the AI/MCP wave and spreads: up to ~$300k/year**: the documented ceiling for a strong solo dev-tool business; higher needs a team and a different model.
- **Spend your energy on reach, not features.** Conversion (1→5%) and price (~$80–99) move the result far less than traffic does. The free web tool's real job is to be the distribution engine.
- **Build the cheap, validated pieces first** (web check/fix/report + fork-a-spec + webhook/auth scaffold + repair). Add the visual builder only as a text-round-trippable layer, and defer the component marketplace until there's proven pull.

### Caveats
Conversion benchmarks are cross-industry; no verified VS-Code/GitHub→paid conversion figure exists. Apidog/Apifox, Bruno, Hoppscotch revenue is private; none anchored here. Low-code market figures ($26–49B) are general app-building, *not* API-spec design, and overstate this TAM by orders of magnitude. Traffic assumptions are illustrative; your actual reach is the single biggest unknown.

*Sources: firstpagesage.com/seo-blog/saas-freemium-conversion-rates · business.daily.dev (PLG dev tools) · siliconangle.com (Stainless ~$1M ARR / $25M Series A) · speakeasy.com/fundraising-series-a · indiehackers.com (solo Mac dev ~$300k) · github.com/APIs-guru/openapi-directory · blog.postman.com (public API network) · postman.com/state-of-api/2025 · apisyouwonthate.com (design-first vs code-first; "All Devtools Die") · learning.postman.com (API Builder deprecated) · developer.apple.com/app-store/small-business-program · vendor pricing pages (Proxyman, TablePlus, Tower), all 2026-06-23.*
