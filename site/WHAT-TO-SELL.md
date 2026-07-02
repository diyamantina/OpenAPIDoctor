# OpenAPIDoctor — What can you actually sell?

The engine is MIT-licensed, so the *validation/repair logic itself is not sellable* — anyone
can use or rebuild it. What sells is the **convenience, automation, hosting, and trust** wrapped
around the free core. The open-source CLI is your marketing funnel; the products below are the
things a team would rather pay for than build and maintain.

Everything here is grounded in what the code already does today:
`--fix` (strip vendor-extension keys, drop `nullable:true` on 3.1, inject `servers`, synthesize
`operationId`), `--corpus` (batch a directory), `--all` (dry-run survey), multi-file `$ref`
resolution (Stitcher), and a Wasm-capable build.

---

## The realistic market

Buyers = teams using **`swift-openapi-generator`** (Apple-backed, growing) on macOS/Linux who hit
`OpenAPIKit` parse failures that produce non-compiling generated code. That's a real, specific,
painful problem — but a **narrow** audience. So: price low, lean on volume + reputation, and don't
expect this alone to replace a salary. The asymmetric upside is *credibility* that converts into
consulting.

---

## Ranked: what to sell

### 1. CI Gate (GitHub Action) — the clearest product 🟢🟢🟢
**What:** A drop-in Action that validates every spec on every pull request, comments the diagnosis
inline, and optionally opens an auto-fix commit — failing the build *before* broken codegen ships.
**Why they pay:** It's recurring pain solved automatically. They're not paying for the check (free
in the CLI); they're paying to never think about it and to not maintain the glue themselves.
**Defensible because:** the PR-bot integration + maintenance is real work teams won't replicate.
**Cost to you:** ~$0 fixed — GitHub Marketplace bills for you.
**Price:** free for public repos (adoption), **$19/org/mo** for private repos + team features.
**Build effort:** medium. **This is where steady revenue comes from.**

### 2. Pro Desktop app + Pro CLI (one-time) 🟢🟢
**What:** A native macOS GUI (drag a spec, see diagnoses, fix with one click, export a report) plus
a Pro CLI with watch mode, batch fixing, and rich HTML/Markdown reports.
**Why they pay:** The GUI is genuinely separate, closed-source work — convenience for devs who
don't want to live in a terminal, and for leads who want shareable reports.
**Defensible because:** closed-source app, not derivable from the MIT core.
**Cost to you:** ~$0 — sell via **Lemon Squeezy** (merchant-of-record, license keys built in,
percentage fee, no monthly).
**Price:** **$39 one-time, lifetime.** One-time beats subscription for a dev tool this size.
**Build effort:** medium-high (the app UI).

### 3. Sponsorship / support tiers 🟢
**What:** Named GitHub Sponsors tiers — priority issue response, logo on the site/README, roadmap
input, early access to Pro ("sponsorware").
**Why they pay:** Companies depending on the tool expense small sponsorships easily; some want a
human to answer when a spec breaks their build.
**Cost to you:** $0. **Price:** $5 / $25 / $100+ /mo tiers. **Build effort:** trivial (you have the link).

### 4. Consulting / retainers — highest $/hour 🟢🟢
**What:** "Hire me for Swift + OpenAPI tooling." You built three interlocking libraries
(OpenAPIDoctor, PureYAML, Stitcher) — that's rare expertise.
**Why they pay:** Teams stuck on codegen pipelines will pay for hours, not products.
**Cost to you:** $0 fixed. **Price:** your hourly/day rate. **Build effort:** a CTA line + a calendar link.
**Realistically out-earns 1–3 combined**, and the free tool is what generates the leads.

### 5. Hosted org dashboard — defer ⚠️
**What:** A dashboard tracking clean/fixable/broken specs across an org's repos over time.
**Why deferred:** This one needs a backend → recurring hosting cost, which fights your
"minimal expenses" goal. Only build it after the Action proves demand, and price it to cover hosting.

---

## The license boundary — decide this now, not later

Keep the **engine MIT** (it earns the stars that drive everything). Put every paid feature in a
**separate, closed repo/binary from day one**:

| Free, MIT (the funnel) | Paid, closed (the products) |
|---|---|
| Core library + `openapi-doctor` CLI | GitHub Action PR-bot + auto-fix commits |
| In-browser Wasm validator | Native macOS app + Pro CLI extras |
| `--fix`, `--corpus`, `--all`, multi-file | Org dashboard, hosted reports |
| Community GitHub support | Priority support, consulting |

Retrofitting this split later is painful. Draw the line today: **engine = free; orchestration,
UI, hosting, and support = paid.**

---

## Suggested first move

Ship the **GitHub Action (free tier)** + the **in-browser validator site** first. Both are near-zero
cost and build the audience. Turn on the paid Action tier and the consulting CTA the moment people
are using the free pieces. Add the Pro app only once there's a waitlist asking for it.

Recurring cost across all of this stays at roughly **just the domain**; GitHub and Lemon Squeezy are
percentage-only.
