# GirlTea — Flutter app

The client for GirlTea, an anonymous closed-group community app. Talks to the
Supabase backend defined in the repo root (`schema/` + `supabase/`).

## What's built

- **Auth** — email OTP sign-in via Supabase Auth
- **Group feed** — reads through the `posts_feed` view (anonymity-preserving)
- **Posts** — text, image, video, and voice
  - Voice notes recorded in-browser (live timer, 180s auto-stop)
  - Video pick-from-disk or record, with client-side duration probe (blob
    URL + off-screen `<video>`), a 100 MB size guard, and a 180s cap
  - Media stored in the private `post-media` bucket; feed playback via
    1-hour signed URLs (`SignedImage` / `SignedVideo` / `SignedAudio`)
- **Comments** — single-level threading (a comment may reply to a top-level comment)
- **Upvotes** — one tap per user, denormalized count maintained by a DB trigger

## Running locally

The app points at a local Supabase stack (see `lib/config.dart`). Bring the
backend up first (Supabase CLI, backed by Colima or Docker), then:

```bash
flutter pub get
flutter run -d web-server --web-port 8088 --web-hostname 127.0.0.1
```

Open http://127.0.0.1:8088. Sign in with a demo user (e.g. `diya@example.com`)
and read the OTP from Mailpit (http://127.0.0.1:54324).

> Note: `web-server` mode does not hot-reload on save — press `R` in the
> terminal (or restart) after code changes, then hard-refresh the browser.

## Key dependencies

`supabase_flutter`, `image_picker`, `record`, `just_audio`, `video_player`,
`http`, `uuid`.
