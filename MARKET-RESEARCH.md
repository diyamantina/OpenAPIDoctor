# OpenAPIDoctor: Market Research

*Prepared June 23, 2026. Reframed around the core insight: this is a **spec** tool, not a Swift tool. Swift/OpenAPIKit is the current engine and the credibility wedge; the market is every team that feeds an OpenAPI spec into anything downstream.*

---

## TL;DR verdict

**The problem is real, broad, and growing, but the MIT core itself is not sellable, and the donation ceiling is low.** Invalid/messy OpenAPI specs break code generation in *every* language, and a new AI/MCP wave (2025–2026) has made "clean spec" matter more than ever. There is a genuine gap for a **focused, low-cost, privacy-first "fix my spec so it works downstream" tool**, but that gap is *already partly occupied by a product literally called "OpenAPI Doctor"* (doctor.pb33f.io), and the enterprise end is crowded with funded players (Speakeasy raised ~$26M; Stainless was just absorbed by Anthropic).

**Honest revenue read:** as a solo, MIT-licensed dev tool relying on sponsorship, expect **$0–200/month**. A respected niche tool with a maintained presence tops out around **$1–1.5k/month**. Six figures requires changing the model: closed-source paid add-ons sold to *companies*, or B2B retainers/consulting. Never the donate button alone.

**Lowest-cost path that actually earns:** keep the engine free as a funnel; monetize a **team/CI "spec-quality gate"** (ideally with an MCP-readiness angle) and **consulting**. Lead with the AI/MCP differentiator; it's the freshest, least-crowded wedge.

---

## 1. The pain is broad and cross-language (strong demand signal)

The "messy spec breaks codegen" problem is **not Swift-specific**. Verified GitHub issue counts (queried 2026-06-23):

| Generator | Total issues | "invalid spec" | "nullable" | "does not compile" |
|---|---|---|---|---|
| OpenAPITools/openapi-generator (50+ languages) | ~9,950 | ~721 | ~773 | ~246 |
| microsoft/kiota (.NET/multi) | ~1,544 | n/a | n/a | ~70 |
| apple/swift-openapi-generator | ~459 | n/a | ~35 | ~30 |

Real **vendor** specs break real generators: Pipedrive's public spec breaks Kiota's Go output; Fannie Mae and Precisely APIs break openapi-generator's Java output. The same failure modes recur everywhere: `nullable` handling, `anyOf`/`oneOf`/`allOf` composition, non-`x-` vendor keys, broken `$ref`s. An independent validator's corpus of 7,039 specs found `nullable`-deprecated 24,539×, `oneOf` violations 19,772×, missing-`$ref` 19,136×.

A whole tooling category exists *because* of this pain (stars as proxy for felt need): Spectral ~3,118★, Redocly CLI ~1,460★, swagger-parser ~1,201★, vacuum ~1,089★. A long-running Hacker News thread captures the sentiment bluntly: client codegen "*straight up doesn't compile*" across Java, Scala, Ruby, Python, TS, C#, Go.

*Sources: github.com/OpenAPITools/openapi-generator/issues · github.com/microsoft/kiota/issues · github.com/apple/swift-openapi-generator/issues · apinotes.io/blog/common-openapi-spec-errors-and-how-to-fix-them · news.ycombinator.com/item?id=36145131 · github.com/stoplightio/spectral · github.com/daveshanley/vacuum*

---

## 2. The AI / MCP tailwind: the freshest wedge

Since MCP launched (late 2024), "your spec quality determines your AI tooling quality" has become a loud, recurring theme, and it's the part of the market least owned by incumbents.

- An independent academic study (arXiv 2507.16044, "From REST to MCP") on 80 real OpenAPI contracts found generation failures "*often arise when OpenAPI specifications are incomplete or incorrect relative to vendor behavior, preventing valid tool schemas.*"
- Vendors converged on this within ~12 months: Stainless ("*LLMs get confused when there's too much indirection*"; shipped "Transforms" to fix imperfect specs), Speakeasy ("*the quality of your resulting MCP tools depends on the quality of your OpenAPI document*"), Zuplo ("*loose or ambiguous schemas will cause agents to fail repeatedly*"), Redocly, Fern.
- Strategic signal: **Stainless announced (May 2026) it is joining Anthropic and winding down hosted products**, confirming the space matters, and vacating a premium competitor.

*Sources: arxiv.org/abs/2507.16044 · stainless.com/blog/lessons-from-openapi-to-mcp-server-conversion · zuplo.com/blog/ai-agents-are-coming-for-your-apis · speakeasy.com/mcp/tool-design*

---

## 3. Market size (context, not a precise TAM)

There is **no clean "OpenAPI spec tooling" market figure**; it's a thin slice of API management. Use ranges, never a single number.

- **Developers:** ~47.2M globally (SlashData, 2025; ~36.5M professional). JetBrains' stricter count is ~19.6M professional.
- **OpenAPI/API-first adoption:** Postman 2025 State of the API (n≈5,700): 82% of orgs have some API-first approach; 93% of API teams hit collaboration blockers driven by "inconsistent documentation and definitions"; 55% struggle with inconsistent docs. SmartBear 2023 (n≈1,100): 71% use a standardized design approach (OpenAPI), and 51% rank API standardization their top issue.
- **API management market (outer-bound proxy only):** published 2025 valuations span ~$6–9B with CAGRs ~17–34% depending on the firm. The spread *is* the finding; spec validation/repair is a sliver of this.

*Caveat:* the precise count of teams that hit broken specs is **not surveyed**; it's strongly evidenced qualitatively (§1, §2) but any sizing is a derived estimate.

*Sources: slashdata.co (2025) · voyager.postman.com/doc/postman-state-of-the-api-report-2025.pdf · smartbear.com/state-of-software-quality/api · precedenceresearch.com/api-management-market · mordorintelligence.com/industry-reports/api-management-market*

---

## 4. Competitive landscape: where you'd actually fit

**The cheap/open end (lint & validate, mostly no auto-fix, not framed as codegen-prep):**

- **Spectral** (Stoplight/SmartBear): Apache-2.0, the de-facto linter; free.
- **vacuum** (pb33f): MIT, "world's fastest" linter; free.
- **Redocly CLI**: open-source lint/validate; hosted platform paid ($10–24/seat/mo).
- **RateMyOpenAPI** (Zuplo): free, grades specs explicitly on "SDK Generation." Direct validation of the problem.
- **Kiota / openapi-generator**: free; validate but **don't auto-repair**.

**⚠️ The direct concept-and-name collision. Read this first:**

- **pb33f "OpenAPI Doctor"** (doctor.pb33f.io), by the author of vacuum, *"Diagnose, validate, test and fix OpenAPI documents."* Apache-2.0 core, free-for-OSS, with pay-per-use / unlimited / **buy-a-license self-hosted-desktop** options. **This is the same name and the same concept you're building.** It is small and single-founder, so the space is contestable, but you cannot ignore it for branding (openapidoctor.com vs doctor.pb33f.io) or positioning.

**The enterprise end (spec-fixing bundled inside pricey platforms, you can't buy just the fix step):**

- **Speakeasy**: SDK/MCP gen + "Suggest" LLM auto-fixer; ~$26M raised; sales-led pricing.
- **Stainless**: premium SDK gen; just joined Anthropic.
- **APIMatic**: validate/lint/auto-fix + SDK; ~$10/mo entry, ~$300/mo/language.
- **Bump.sh**: docs + lint; $50–250/mo (free for OSS on request).
- **Stoplight** (SmartBear): $44–453/mo tiers.

**The gap:** a focused, **low-cost, standalone, runs-locally** "make this spec safe for codegen/MCP" tool. The open tools lint but don't fix or frame around codegen; the paid tools weld fixing to $250–600+/mo platforms or cloud LLMs that require **uploading your spec**. **Privacy / local-only is the single strongest differentiator** (Speakeasy Suggest and APIMatic are cloud-based), but note pb33f's Doctor already offers a self-hosted/desktop option.

*Sources: stoplight.io/open-source/spectral · github.com/daveshanley/vacuum · doctor.pb33f.io · redocly.com/pricing · apimatic.io · bump.sh/pricing · speakeasy.com · ratemyopenapi.com (Zuplo) · stainless.com*

---

## 5. Monetization reality: the brutal version

**The MIT core cannot be sold.** Anyone can copy and run it. Money comes only from the convenience, hosting, support, or proprietary add-ons *around* it. Evidence:

- **GitHub Sponsors:** only ~31% of maintainers who set it up ever receive *anything*; of those, ~39% got just $1. Average individual sponsor ≈ $8/mo; org sponsor ≈ $200/mo (GitHub takes 0% from individuals).
- **Closest analog: azu** (solo maintainer of the *textlint/secretlint* linters, "as a hobby"): **~$14,600 in 2023 (~$1.2k/mo)**. That's a realistic *good* outcome for a respected niche linter.
- **The outliers prove the rule:** Caleb Porzio hit ~$112k/yr, but via **gated paid screencasts**, not donations, on a large pre-existing audience. Sidekiq's Mike Perham reached ~$7–10M as a one-person company, via **closed-source Pro/Enterprise add-ons sold to businesses**, not the MIT core. Filippo Valsorda earns a full-time living via **B2B retainers** from ~6 funded companies. None of these is passive; none is the donate button.
- **Paid GitHub Marketplace Action:** possible (verified-org only; GitHub takes 5%; $500/mo payout minimum) but **no credible solo-revenue examples**: a weak, unproven channel.
- **One-time license (Lemon Squeezy 5%+$0.50 / Gumroad 10%+$0.50, both merchant-of-record handling VAT):** works for assets/courses; **no evidence a free-to-replicate CLI earns meaningfully** this way.

**Willingness-to-pay for dev-time CLIs/linters is structurally weak**: individuals resist paying for tools they can self-host; budget lives at the *team* level, and only when the tool touches production reliability, security, or compliance.

| Scenario | Channel | Realistic monthly |
|---|---|---|
| Most likely (passive sponsor button) | GitHub Sponsors | **$0–200** |
| Good (respected tool + maintained presence) | Sponsors + corp pools | **$1,000–1,500** |
| Strong (large audience + gated content) | Sponsorware | up to ~$9k (needs audience work) |
| Business (closed add-ons sold to companies) | Open-core / B2B | $5k–80k+ (real sales, not passive) |

*Sources: arxiv.org/abs/2111.13323 · arxiv.org/abs/2202.05751 · docs.github.com/sponsors · dev.to/azu/my-github-sponsors-revenue-2023-1m3d · calebporzio.com · saas.group (Sidekiq) · words.filippo.io/professional-maintainers · docs.lemonsqueezy.com/help/getting-started/fees · docs.github.com/apps/github-marketplace*

---

## 6. Recommendation

1. **Reposition the product as language-agnostic**: "diagnose & repair any OpenAPI spec so it works downstream (codegen for any language, MCP/AI tools, docs, gateways)." Swift is your proof of credibility and the engine, not the pitch. (Note: the engine is bound to OpenAPIKit today; broadening to other parsers/rulesets is a real engineering step, not just marketing.)
2. **Lead with the AI/MCP angle**: "is your spec ready for AI agents / MCP tools?" It's the freshest, least-crowded, fastest-growing framing, and it's vendor-validated.
3. **Lean on privacy/local-only**: the one thing the funded cloud players can't easily match.
4. **Resolve the name collision** with pb33f's "OpenAPI Doctor" before investing in the brand: differentiate sharply or reconsider naming. You own openapidoctor.com, which is an asset, but they hold the same name and concept.
5. **Set expectations honestly:** treat direct product revenue as a few hundred $/month most likely. The real payoff is **reputation → consulting/retainers** (the Valsorda model), plus an optional **team/CI gate** sold to companies (the only spot with genuine willingness-to-pay).
6. **Keep recurring cost ≈ the domain.** Free open-core funnel; sponsor tiers; consulting CTA; merchant-of-record (Lemon Squeezy) only if/when you ship a paid add-on. Avoid hosted infrastructure until demand is proven.

---

### Confidence & gaps

- **High confidence:** the pain is broad and cross-language; a linter/fixer category exists and is well-used; the MIT core isn't directly sellable; sponsorship ceilings are low; the pb33f name/concept collision is real.
- **Medium confidence:** AI/MCP tailwind strength (much of the evidence is vendor-published; the academic study is the independent anchor).
- **Known gaps / flagged:** no survey quantifies *how many* teams hit broken specs (qualitatively strong, numerically derived); API-management market dollar figures vary wildly by firm; several competitor prices are sales-led/"talk to us"; Stainless→Anthropic is search-sourced.
