# GirlTea Roadmap

> **The one thing this roadmap protects:** the loop
> *something happens → "I need to tell my girls" → open GirlTea → Spill → they
> respond → I feel closer to them.* If a piece of work doesn't make those 90
> seconds better, it waits.

GirlTea is now **technically ahead of its product maturity**. The backend has
auth, RLS, storage policies, invite links, voting, moderation, erasure, multiple
media types, themes, aliases, reactions, and a Memories schema. That's enough
infrastructure. The job now is **not** "what else can we add?" — it's turning what
exists into an extremely good **3-person experience** and getting it onto phones.

So: **breadth is frozen.** New feature ideas go to the *Later / Parking lot*
section, not into the build.

---

## The product, restated

**Problem.** Close friendships become passive as adult life gets busier. The
people who once knew everything about your life gradually know only the headlines.

**Solution.** Private little rooms that make it easy to actually talk to your
people again. Video is the mechanism, circles are the social structure,
ephemerality removes permanence, themes create ownership, memories preserve what
matters.

This is **not** a community/Reddit product and **not** about meeting strangers.
"Maintain close relationships" and "meet like-minded strangers" are different
jobs-to-be-done; we're only doing the first one in V1.

---

## P0 — required before any real launch

| # | Build | Why |
|---|---|---|
| 1 | **Native iOS/Android build** | The product is "lying in bed → open phone → record a rant." It belongs on phones — camera, mic, push, share sheet, deep links, background uploads. Flutter web on Render is a dev/beta harness, not the product. |
| 2 | **Push notifications** | A social loop doesn't work if people must *remember* to open a URL. Friend records "girls I need you 😭" and nobody knows = dead product. **Note:** web push is unreliable/absent on iOS Safari, so this is effectively the *same bet as native* — sequence them together. Start with transactional notifications only (someone spilled / replied / saved / reacted). Be very careful with "your girls haven't heard from you lately" — do not become Duolingo for friendship. |
| 3 | **Bulletproof video/voice recording, upload & recovery** | The hero behaviour. Client-side compression (100 MB videos wreck bandwidth economics), upload progress, retry/resume on bad connections, and **draft recovery** — losing one emotionally vulnerable recording can lose the user forever. Server-side duration validation stays post-MVP; *never losing a recording* matters far more. |
| 4 | **Circle → Spill in seconds** | Collapse the multi-step composer. Circle context already = audience. A big persistent `☕ SPILL` on the circle screen; hold = video, adjacent tap = voice/photo/text. Beat WhatsApp on *emotional initiation* (we can't beat it on general messaging). |
| 5 | **Invite / deep-link onboarding** | The viral loop. "Niharika saved you a seat ☕" → tap → in the circle. `fn_resolve_invite` already returns the inviter's name (migration 028). |
| 6 | **Analytics + crash reporting** | Learn what actually works. Events: `circle_created`, `invite_sent/accepted`, `spill_started/completed/viewed`, `reply_created`, `reaction_created`, `memory_saved`, `second_circle_created`. **No private post content in analytics.** Crash/error/upload-failure/playback-failure/auth-failure reporting. |
| 7 | **Privacy/security audit** | We're storing intimate video. Rate limiting, upload/MIME validation, malicious-file handling, invite brute-force protection, storage quotas, session revocation. Test matrix: auth, RLS, cross-circle access attempts, invite abuse, expired invites, media authorization, deletion, banned-member access, account erasure. |

### P0 correctness fix (not a "feature")

- **Join-flow bootstrapping bug.** `fn_cast_join_vote` requires a 2-member quorum
  to admit — but a brand-new circle has exactly **one** active member, so friend #2
  can *never* be admitted. Fix: **invited-by-a-member → join immediately** for
  private circles. Optionally let the creator configure *"anyone can invite"* vs
  *"invites require approval."* The parliamentary vote makes sense for future
  10–50-person communities, not a 3-person friendship. This is a bug, not just a
  UX-heaviness complaint.

---

## P1 — the differentiation, right after launch mechanics work

| # | Build | Why |
|---|---|---|
| 8 | **30-day expiry ("tea gets cold ☕")** | Ephemerality is core to the category (competitors lean on it). Default: posts fade after 30 days → then "Save to Memories." Creates the product tension: *conversations are temporary, memories are intentional.* Needs `expires_at` + a purge job — **currently out of scope in the schema**, moving here. |
| 9 | **Memories UI** | Gives expiry meaning. Not "Saved Posts" — a scrapbook: *"School Witches 🍒 / Our memories / August 2026"*, and eventually *"Our Year in Tea — 2026: 12 months, 147 spills, 623 replies, 38 memories kept."* This is where real emotional switching cost lives. `saved_posts` schema (026) already exists. |
| 10 | **Video/voice replies, first-class** | The behaviour is friend talks → friend responds. Comments today support text/image/voice but **not video** and are single-level. Add video replies. Single-level threading is fine — don't build Slack. |
| 11 | **Notification privacy controls** | Hide previews: *"New tea in School Witches ☕"* not the post body. Trust feature. |
| 12 | **Biometric app lock** | The content is intimate; a PIN/biometric lock is table stakes for trust in this category. |
| 13 | **Circle rituals / light prompts** | Solve the dry-group problem without spam. *"Sunday Tea ☕ — what happened this week your girls don't know yet?"* Gentle, occasional. **Not streaks, not guilt, not "🔥 47-DAY FRIENDSHIP STREAK."** Reconnection, not addiction. |
| 14 | **Finish circle themes** | Ownership and delight; 8 themes + per-circle accent already exist, wire them fully. |

### P1 product cleanup (small, on-brand)

- **Kill upvotes in the UI.** "▲ 3" under *"I'm struggling with something with my
  parents"* is wrong for GirlTea. Remove the upvote UI entirely; keep the
  `post_upvotes` table for migration compatibility. Reactions: ❤️ Love · 🫂 Hug ·
  😭 Felt this · 😂 Dead · ☕ Tea · ✨ Proud of you — and show *who*
  ("Rhea & Ananya sent love") not counts. `post_reactions` + the alias-safe feed
  (027) already support this.
- **Pull discoverable/public groups out of the V1 surface.** Keep `LINK_ONLY`
  only. No discovery, no "women near Bangalore," no follower system, no
  suggestions. The schema can keep `DISCOVERABLE`; the product just won't expose
  it. (Communities can become a *separate* surface later if users demand it.)
- **Strip onboarding to almost nothing.** Ask: *"What should your girls call
  you?"* + birthday + optional avatar → then "Create a circle / I have an invite."
  Drop gender/employment/profession at signup — gender only matters if we enforce
  gender-based public membership, which V1 removes. Collect as little intimate
  info as possible; we're selling trust.
- **Privacy as a product story, not just RLS.** On the recording screen especially,
  say it out loud: *"🔒 Only School Witches can see this."* That's the moment the
  user decides whether to trust the app with something real.

---

## Later / parking lot (do NOT build now)

- **E2EE for private posts/videos.** Strong long-term privacy proposition and a
  real competitive gap in this category. **But** it's an architecture fork, not a
  bolt-on: the current `post_reactions_feed` / `saved_posts_feed` views, server-side
  moderation, and erasure all assume the server can *read* content. E2EE means it
  can't. Don't market *"what happens in GirlTea stays in GirlTea"* until the
  architecture can justify it. Not needed for a 20-person alpha.
- **Screenshot deterrence / view-once / download permissions.** Meaningful controls
  where the platform allows; never promise technically impossible cross-platform
  screenshot prevention.
- **Discoverable communities** as a distinct product surface.
- **Monetization.** Retention first.

---

## Engineering hygiene (parallel track, before public launch)

- **Refactor `main.dart`.** It's one ~5,500-line file (auth + feeds + composer +
  moderation). Split into `features/{auth,onboarding,circles,invites,spill,`
  `reactions,memories,notifications,moderation,profile}` with
  `data/domain/presentation` where complexity warrants — *without*
  architecture-astronauting it. One giant file becomes miserable once native media,
  expiry, analytics, and mobile lifecycle land.
- **Operations.** Backups, migration discipline, a staging environment, rollback
  strategy, secret management (**rotate the exposed service_role key / DB password /
  Resend key**), monitoring, an incident process.

---

## Launch: 10 circles, not a country

Don't launch to India. Don't even launch to Bangalore. **Launch to ~10 circles /
30–40 people** for six weeks — the four real ones (School, Married, Gym, Writing)
plus ~six circles owned by other women.

Dashboard should answer:

- **Activation** — of people invited, how many join?
- **First value** — how fast does the first person Spill, and how fast does someone
  respond?
- **Reciprocity** *(the key early metric)* — does someone *other than the circle
  creator* independently start a Spill?
- **Retention** — how many circles have ≥2 contributing members at W1 → W2 → W4 →
  W6?
- **Expansion** *(the organic growth engine)* — how many invited users create their
  own second circle?

**The test that actually matters.** A circle responding to *your* prompts can fool
you. The real signal: one Wednesday at 11:38pm, a friend opens GirlTea on her own
and records *"okay, I need to tell you girls what happened today…"* — unprompted.
And then someone creates *their own* circle and invites *their* people. That's
product-market pull.

If GirlTea makes that loop better than WhatsApp, there's a product. If it doesn't,
eight themes, 29 migrations, and flawless democratic governance won't save it.
