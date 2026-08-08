# GirlTea — Flutter app

The client for GirlTea, an anonymous closed-group community app. Talks to the
Supabase backend defined in the repo root (`schema/` + `supabase/`).

## What's built

- **Auth** — email OTP sign-in via Supabase Auth
- **URL routing** — real, shareable paths via `go_router`:
  - `/home` — overview of the circles you're in
  - `/:group-slug` — a circle's feed (readable slug, e.g. `/college-girls`)
  - `/:group-slug/:postId` — a single post and its tea (short post id)
  - `/me` — your profile
  Deep links resolve on a cold load; auth redirects bounce between `/login`
  and `/home`.
- **Three-pane shell** — on wide screens: left circle rail · feed · right
  circle panel, kept mounted across navigation; a single pane on mobile.
- **Global top bar** — 🍵 brand (→ home) · centered **Spill** (compose into the
  current circle) · profile menu (View Profile / Display Mode / Log Out).
- **Display mode** — light / dark / system, persisted to browser localStorage.
- **Group feed** — reads through the `posts_feed` view (anonymity-preserving)
- **Posts** — text, image, video, and voice
  - Voice notes recorded in-browser (live timer, 180s auto-stop)
  - Video pick-from-disk or record, with client-side duration probe (blob
    URL + off-screen `<video>`), a 100 MB size guard, and a 180s cap
  - Media stored in the private `post-media` bucket; feed playback via
    1-hour signed URLs (`SignedImage` / `SignedVideo` / `SignedAudio`)
- **The Tea** — post comments with single-level threading ("Spill" / "Spill
  More"), read through the `comments_feed` view
- **Upvotes** — one tap per user, denormalized count maintained by a DB trigger

## Running locally

The app points at a local Supabase stack (see `lib/config.dart`). Bring the
backend up first (Supabase CLI, backed by Colima or Docker), then:

```bash
flutter pub get
flutter run -d web-server --web-port 8088 --web-hostname 127.0.0.1
```

Open http://127.0.0.1:8088. Sign in with a demo user (e.g. `diya@example.com`)
and read the OTP from Mailpit (http://127.0.0.1:54324). For a faster loop,
`../scripts/dev-code.sh` requests a code and prints it straight from Mailpit —
no inbox digging. (GoTrue has no fixed email OTP, so a truly static "super
code" isn't possible on this stack.)

> Note: `web-server` mode does not hot-reload on save — press `R` in the
> terminal (or restart) after code changes, then hard-refresh the browser.

## Key dependencies

`supabase_flutter`, `go_router`, `image_picker`, `record`, `just_audio`,
`video_player`, `http`, `uuid`.
