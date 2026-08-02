# GirlTea — Query Reference

Every database operation the Flutter app makes, organized by domain.
The read/write split is enforced here: **reads from views, writes to base tables,
mutations through RPC functions.**

`Tables` constants in `core/supabase.dart` should match these exactly.

---

## Auth & Profile

### Check if profile exists (after OTP verify)

```dart
final profile = await supabase
    .from('users')
    .select()
    .eq('id', supabase.auth.currentUser!.id)
    .maybeSingle();
// null → show onboarding; non-null → go to hub
```

Target: `users` (SELECT — own profile only via RLS).

### Create profile (onboarding submit)

```dart
await supabase.from('users').insert({
  'id': supabase.auth.currentUser!.id,
  'auth_subject': supabase.auth.currentUser!.phone
      ?? supabase.auth.currentUser!.email,
  'display_name': name,
  'date_of_birth': dob,               // ISO: '2000-01-15'
  'gender': gender,                    // enum string: 'WOMAN', 'MAN', etc.
  'gender_self_describe': selfDescribe, // null unless gender == 'SELF_DESCRIBE'
  'employment_status': employment,     // 'WORKING', 'NOT_WORKING', 'PREFER_NOT_TO_SAY'
  'profession': profession,            // null unless employment == 'WORKING'
  'locale': 'en-IN',
  'country_code': 'IN',
});
```

Target: `users` (INSERT — `WITH CHECK (id = auth.uid())`).

### Update profile

```dart
await supabase.from('users').update({
  'display_name': newName,
  // ... any mutable fields
}).eq('id', supabase.auth.currentUser!.id);
```

Target: `users` (UPDATE — own row only).

### RPC: check profile exists (alternative)

```dart
final hasProfile = await supabase.rpc('fn_has_profile');
// returns bool
```

---

## Groups

### List discoverable groups (suggestions)

```dart
final groups = await supabase
    .from('groups')
    .select()
    .eq('visibility', 'DISCOVERABLE')
    .eq('is_deleted', false)
    .order('member_count', ascending: false);
```

Target: `groups` (SELECT — RLS shows DISCOVERABLE to all, LINK_ONLY to members only).

### Get a specific group (by ID or invite link resolution)

```dart
final group = await supabase
    .from('groups')
    .select()
    .eq('id', groupId)
    .single();
```

### Create a group

```dart
// 1. Insert the group
final group = await supabase.from('groups').insert({
  'name': name,
  'description': description,
  'policy': policy,           // 'WOMEN_ONLY', 'MIXED', 'GENDER_NEUTRAL'
  'visibility': visibility,   // 'LINK_ONLY', 'DISCOVERABLE'
  'category_tags': tags,      // ['school_friends', 'rant']
  'created_by_user_id': supabase.auth.currentUser!.id,
}).select().single();

// 2. Add yourself as OWNER
await supabase.from('group_memberships').insert({
  'group_id': group['id'],
  'user_id': supabase.auth.currentUser!.id,
  'role': 'OWNER',
  'alias': 'fn_generate_alias()',  // see note below
});
```

**Note:** For the alias, call RPC instead of inserting raw:

```dart
// Better: use an RPC that creates group + adds owner atomically
// (to be created as a SECURITY DEFINER function)
```

Target: `groups` (INSERT), `group_memberships` (INSERT — creator only via RLS).

### List my groups

```dart
final myGroups = await supabase
    .from('group_memberships')
    .select('group_id, role, alias, groups(*)')
    .eq('user_id', supabase.auth.currentUser!.id)
    .eq('status', 'ACTIVE');
```

Target: `group_memberships` (SELECT — RLS via `fn_is_group_member`), joined with `groups`.

### List members of a group

```dart
final members = await supabase
    .from('group_memberships')
    .select('role, alias, status, joined_at')
    .eq('group_id', groupId)
    .eq('status', 'ACTIVE');
```

Target: `group_memberships` (SELECT — members only). **Note: does NOT return `user_id` to client.**
If you need to hide `user_id` from the members list, create a `members_feed` view
similar to `posts_feed`. For MVP, `user_id` in memberships is less sensitive than in
posts (members know each other anyway), but evaluate based on product needs.

---

## Invite Links

### Create an invite link

```dart
// Generate a random token client-side, hash it, store the hash
import 'dart:convert';
import 'package:crypto/crypto.dart';

final token = generateRandomToken();  // your util
final hash = sha256.convert(utf8.encode(token)).toString();

await supabase.from('group_invites').insert({
  'group_id': groupId,
  'token_hash': hash,
  'created_by_user_id': supabase.auth.currentUser!.id,
  'max_uses': 50,  // null for unlimited
});

// Share the raw token via WhatsApp/SMS:
// https://girltea.app/join/{token}
```

### Resolve an invite link (user taps the link)

```dart
final hash = sha256.convert(utf8.encode(token)).toString();

final invite = await supabase
    .from('group_invites')
    .select('id, group_id, expires_at, max_uses, use_count, revoked_at')
    .eq('token_hash', hash)
    .maybeSingle();

// Validate: not null, not expired, not revoked, use_count < max_uses
```

**Note:** Invite resolution needs special handling — the user isn't a member yet,
so RLS blocks the SELECT. Options:
1. Public Edge Function that validates the token and returns group metadata
2. A SECURITY DEFINER function `fn_resolve_invite(token_hash)` that returns
   the group info without requiring membership

---

## Join Flow

### Check eligibility

```dart
final eligible = await supabase.rpc('fn_validate_join_eligibility', params: {
  'p_user_id': supabase.auth.currentUser!.id,
  'p_group_id': groupId,
});
// returns bool
```

### Get entry questions for a group

```dart
final questions = await supabase
    .from('group_entry_questions')
    .select()
    .eq('group_id', groupId)
    .order('sort_order');
```

Target: `group_entry_questions` (SELECT — open to all authenticated, they need
to see questions before joining).

### Submit join request + answers

```dart
// 1. Create the join request
final request = await supabase.from('group_join_requests').insert({
  'group_id': groupId,
  'requester_user_id': supabase.auth.currentUser!.id,
  'source': source,  // 'INVITE_LINK', 'SUGGESTION', 'MANUAL_SEARCH'
  'invite_id': inviteId,  // null if not from invite
}).select().single();

// 2. Submit answers
final answers = questions.map((q) => {
  'join_request_id': request['id'],
  'question_id': q['id'],
  'question_version': q['version'],
  'answer_text': answerControllers[q['id']]!.text,
}).toList();

await supabase.from('group_join_request_answers').insert(answers);
```

### List pending join requests (for members to review)

```dart
final requests = await supabase
    .from('group_join_requests')
    .select('*, group_join_request_answers(*)')
    .eq('group_id', groupId)
    .eq('status', 'PENDING')
    .order('created_at');
```

### Cast a join vote

```dart
final result = await supabase.rpc('fn_cast_join_vote', params: {
  'p_join_request_id': requestId,
  'p_vote': 'APPROVE',  // or 'REJECT'
});
// Returns: { request_status, approval_count, quorum_required }
```

**Always use the RPC** — never insert into `group_join_votes` directly.
The function handles membership validation, quorum checking, and atomic admission.

---

## Removal Flow

### Raise a removal request

```dart
final requestId = await supabase.rpc('fn_raise_removal_request', params: {
  'p_group_id': groupId,
  'p_target_user_id': targetUserId,
  'p_reason': 'Posting spam',  // optional
});
// Returns the request UUID. Requester's APPROVE vote is auto-recorded.
```

### List pending removals (for members to review)

```dart
final removals = await supabase
    .from('group_removal_requests')
    .select('*, group_removal_votes(*)')
    .eq('group_id', groupId)
    .eq('status', 'PENDING');
```

### Cast a removal vote

```dart
final result = await supabase.rpc('fn_cast_removal_vote', params: {
  'p_removal_request_id': requestId,
  'p_vote': 'APPROVE',  // or 'REJECT'
});
// Returns: { request_status, approval_count, quorum_required }
```

---

## Posts (Feed)

### Read posts in a group

```dart
final posts = await supabase
    .from('posts_feed')          // VIEW — not 'posts'
    .select()
    .eq('group_id', groupId)
    .order('created_at', ascending: false)
    .range(0, 19);               // pagination
```

Returns: `id`, `group_id`, `author_alias`, `type`, `body`, `media_url`,
`duration_seconds`, `thumbnail_url`, `upvote_count`, `created_at`,
`updated_at`, `is_mine`.

**Does NOT return:** `author_user_id`, `is_deleted`, `deleted_at`.

### Filter by type

```dart
final videos = await supabase
    .from('posts_feed')
    .select()
    .eq('group_id', groupId)
    .eq('type', 'VIDEO')
    .order('created_at', ascending: false);
```

### Create a post

```dart
// 1. Get your alias for this group
final membership = await supabase
    .from('group_memberships')
    .select('alias')
    .eq('group_id', groupId)
    .eq('user_id', supabase.auth.currentUser!.id)
    .single();

// 2. Insert the post
await supabase.from('posts').insert({  // BASE TABLE — not 'posts_feed'
  'group_id': groupId,
  'author_user_id': supabase.auth.currentUser!.id,
  'author_alias': membership['alias'],  // snapshot from membership
  'type': 'TEXT',
  'body': bodyController.text,
});
```

### Create a media post (with storage upload)

```dart
// 1. Upload to storage
final path = '$postId/${file.name}';
await supabase.storage.from('post-media').upload(path, file);
final url = supabase.storage.from('post-media').getPublicUrl(path);

// 2. Insert post with media_url
await supabase.from('posts').insert({
  'group_id': groupId,
  'author_user_id': supabase.auth.currentUser!.id,
  'author_alias': membership['alias'],
  'type': 'VIDEO',  // or 'IMAGE', 'VOICE'
  'media_url': url,
  'duration_seconds': duration,  // null for IMAGE
  'body': captionController.text,  // optional caption
});
```

### Soft-delete a post (own posts only)

```dart
await supabase.from('posts').update({
  'is_deleted': true,
  'deleted_at': DateTime.now().toIso8601String(),
}).eq('id', postId);
// RLS ensures author_user_id = auth.uid()
```

---

## Comments

### Read comments on a post

```dart
final comments = await supabase
    .from('comments_feed')       // VIEW — not 'comments'
    .select()
    .eq('post_id', postId)
    .order('created_at');
```

### Create a comment

```dart
await supabase.from('comments').insert({  // BASE TABLE
  'post_id': postId,
  'author_user_id': supabase.auth.currentUser!.id,
  'author_alias': membership['alias'],
  'type': 'TEXT',
  'body': commentController.text,
});
```

---

## Upvotes

### Upvote a post

```dart
await supabase.from('post_upvotes').insert({
  'post_id': postId,
  'user_id': supabase.auth.currentUser!.id,
});
// Trigger auto-increments posts.upvote_count
// PK constraint prevents double-tap (throws on duplicate)
```

### Remove upvote

```dart
await supabase.from('post_upvotes')
    .delete()
    .eq('post_id', postId)
    .eq('user_id', supabase.auth.currentUser!.id);
// Trigger auto-decrements posts.upvote_count
```

### Check if I upvoted

```dart
final upvote = await supabase
    .from('post_upvotes')
    .select()
    .eq('post_id', postId)
    .eq('user_id', supabase.auth.currentUser!.id)
    .maybeSingle();
// non-null → already upvoted
```

---

## Reports

### File a report

```dart
await supabase.from('reports').insert({
  'target_type': 'POST',  // or 'COMMENT', 'USER', 'GROUP'
  'target_id': targetId,
  'reporter_user_id': supabase.auth.currentUser!.id,
  'reason': reasonController.text,
});
```

---

## Entry Questions (Admin)

### Add entry questions (group creator)

```dart
await supabase.from('group_entry_questions').insert({
  'group_id': groupId,
  'sort_order': 1,
  'prompt': 'Which school batch are you from?',
  'question_type': 'SHORT_TEXT',
  'is_required': true,
});
```

### Update a question

```dart
await supabase.from('group_entry_questions').update({
  'prompt': 'Updated question text',
  'version': currentVersion + 1,
}).eq('id', questionId);
```

---

## Table / View / RPC Reference

| Operation | Target | Type |
|---|---|---|
| Read posts | `posts_feed` | View |
| Read comments | `comments_feed` | View |
| Write posts | `posts` | Table |
| Write comments | `comments` | Table |
| Read/write users | `users` | Table |
| Read/write groups | `groups` | Table |
| Read memberships | `group_memberships` | Table |
| Read/write invites | `group_invites` | Table |
| Read/write entry questions | `group_entry_questions` | Table |
| Read/write join requests | `group_join_requests` | Table |
| Read/write join answers | `group_join_request_answers` | Table |
| Read upvotes | `post_upvotes` | Table |
| Write upvotes | `post_upvotes` | Table |
| Write reports | `reports` | Table |
| Cast join vote | `fn_cast_join_vote` | RPC |
| Cast removal vote | `fn_cast_removal_vote` | RPC |
| Raise removal | `fn_raise_removal_request` | RPC |
| Check eligibility | `fn_validate_join_eligibility` | RPC |
| Check profile exists | `fn_has_profile` | RPC |
| Get my profile | `fn_my_profile` | RPC |
| Generate alias | `fn_generate_alias` | RPC (internal) |

---

## Things to build as RPCs (not yet created)

| Function | Why |
|---|---|
| `fn_create_group_with_owner` | Atomically create group + insert owner membership with alias |
| `fn_resolve_invite` | SECURITY DEFINER to resolve invite token for non-members |
| `fn_leave_group` | Set membership to LEFT, decrement count, handle last-member edge case |
