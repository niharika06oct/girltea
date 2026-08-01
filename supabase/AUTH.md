# Supabase Auth Setup

## Overview

GirlTea uses **Supabase Auth** with phone or email OTP (one-time password).
No passwords, no social login — just enter your phone number or email, get a
code, enter it, and you're in.

## Auth Flow

```
┌─────────┐                               ┌──────────────┐
│  Flutter │  1. Enter phone / email       │   Supabase   │
│   App    │ ─────────────────────────────→│     Auth     │
│          │                               │              │
│          │  2. OTP sent (SMS / email)    │              │
│          │ ←─────────────────────────────│              │
│          │                               │              │
│          │  3. Enter OTP code            │              │
│          │ ─────────────────────────────→│              │
│          │                               │              │
│          │  4. Session token returned     │              │
│          │ ←─────────────────────────────│              │
└─────────┘                               └──────────────┘
      │
      │  5. Check: does this user have a profile?
      │     SELECT * FROM users WHERE id = auth.uid()
      │
      ├── No  → Show onboarding screen
      │         (name, DOB, gender, employment)
      │         INSERT INTO users (id, auth_subject, ...)
      │
      └── Yes → Go to group hub
```

### Why profile is separate from auth

Supabase Auth creates a row in `auth.users` on signup with just a phone/email
and UUID. Our `users` table has required fields (display_name, date_of_birth)
that don't exist at signup time.

Instead of making those nullable, the app checks if a profile exists after
authentication:
- **No profile** → onboarding screen (required before any other action)
- **Has profile** → proceed to group hub

The `users.id` is set to `auth.users.id` (same UUID) so they're linked by PK.

## Setup Instructions

### 1. Enable Phone OTP (for India-first launch)

1. In the Supabase dashboard, go to **Authentication** → **Providers**
2. Enable **Phone**
3. You need an SMS provider. Options:
   - **Twilio** — most popular, pay-per-SMS (~$0.01/SMS to India)
   - **MessageBird** — alternative
   - **Vonage** — alternative
4. Enter your SMS provider credentials (Account SID, Auth Token, Sender number)
5. Set OTP expiry: **5 minutes** (default, reasonable)

### 2. Enable Email OTP (as fallback)

1. In **Authentication** → **Providers**, enable **Email**
2. In **Authentication** → **Settings**:
   - Disable "Enable email confirmations" (you're using OTP, not confirmation links)
   - Enable "Enable email OTP" (or "Use OTP instead of magic link")
3. Supabase sends emails via built-in SMTP on the free plan (rate-limited)
4. For production: configure a custom SMTP (e.g. Resend, SendGrid, Mailgun)

### 3. Auth Settings

In **Authentication** → **Settings**:

| Setting | Recommended value |
|---|---|
| OTP expiry | 300 seconds (5 minutes) |
| OTP length | 6 digits |
| Rate limit (per hour) | 10 per IP (prevents abuse) |
| Minimum password length | N/A (no passwords) |
| Enable signup | Yes |

### 4. Get your project credentials

In **Settings** → **API**:
- **Project URL**: `https://xxxxx.supabase.co`
- **Anon public key**: `eyJhb...` (embed in Flutter app)

These go into your Flutter app's Supabase initialization.

## Flutter Integration

```dart
// In main.dart
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://xxxxx.supabase.co',
    anonKey: 'eyJhb...',
  );

  runApp(const GirlTeaApp());
}

final supabase = Supabase.instance.client;
```

### Phone OTP

```dart
// Send OTP
await supabase.auth.signInWithOtp(phone: '+91XXXXXXXXXX');

// Verify OTP
final response = await supabase.auth.verifyOTP(
  phone: '+91XXXXXXXXXX',
  token: '123456',
  type: OtpType.sms,
);
```

### Email OTP

```dart
// Send OTP
await supabase.auth.signInWithOtp(email: 'user@example.com');

// Verify OTP
final response = await supabase.auth.verifyOTP(
  email: 'user@example.com',
  token: '123456',
  type: OtpType.email,
);
```

### Check if profile exists (after auth)

```dart
final userId = supabase.auth.currentUser!.id;

final profile = await supabase
    .from('users')
    .select()
    .eq('id', userId)
    .maybeSingle();

if (profile == null) {
  // Navigate to onboarding screen
} else {
  // Navigate to group hub
}
```

### Create profile (onboarding)

```dart
await supabase.from('users').insert({
  'id': supabase.auth.currentUser!.id,
  'auth_subject': supabase.auth.currentUser!.phone ?? supabase.auth.currentUser!.email,
  'display_name': nameController.text,
  'date_of_birth': dobController.text,  // ISO format: 2000-01-15
  'gender': selectedGender,
  'employment_status': selectedEmployment,
  'profession': professionController.text,
  'country_code': 'IN',
  'locale': 'en-IN',
});
```

## SMS Costs (India)

| Provider | Cost per SMS (India) | Free tier |
|---|---|---|
| Twilio | ~$0.01 (₹0.80) | $15 trial credit |
| MessageBird | ~$0.01 | 10 free SMS |

At 100 signups/day = ~$1/day = ~$30/month. Email OTP is free (Supabase
built-in SMTP) but less common for mobile apps in India.

## Security Notes

- OTP codes expire after 5 minutes
- Rate limiting prevents brute-force (10 attempts/hour/IP)
- No passwords stored — eliminates password leak risk
- Session tokens managed by Supabase SDK (auto-refresh)
- `auth_subject` stores the phone/email for reference, not for auth
