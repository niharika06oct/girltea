import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: Config.supabaseUrl,
    anonKey: Config.supabaseAnonKey,
  );
  runApp(const GirlTeaApp());
}

final supabase = Supabase.instance.client;

const _pink = Color(0xFFD6336C);

class GirlTeaApp extends StatelessWidget {
  const GirlTeaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GirlTea',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: _pink,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const AuthGate(),
    );
  }
}

/// Shows the login screen when signed out, the hub when signed in.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: supabase.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = supabase.auth.currentSession;
        if (session == null) return const LoginScreen();
        return const HubScreen();
      },
    );
  }
}

// ============================================================
// Login — email OTP (local codes arrive in Mailpit :54324)
// ============================================================
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController(text: 'diya@example.com');
  final _otpController = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;
  String? _error;

  Future<void> _sendCode() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await supabase.auth.signInWithOtp(email: _emailController.text.trim());
      setState(() => _codeSent = true);
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await supabase.auth.verifyOTP(
        email: _emailController.text.trim(),
        token: _otpController.text.trim(),
        type: OtpType.email,
      );
      // AuthGate reacts to the session change automatically.
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('🍵',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 56)),
                const SizedBox(height: 8),
                Text(
                  'GirlTea',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(color: _pink, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  'Vent. Support. Spill the tea.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _emailController,
                  enabled: !_codeSent,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_codeSent) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _otpController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '6-digit code (check Mailpit :54324)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : (_codeSent ? _verify : _sendCode),
                  style: FilledButton.styleFrom(backgroundColor: _pink),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: _busy
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Text(_codeSent ? 'Verify & sign in' : 'Send code'),
                  ),
                ),
                if (_codeSent)
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                              _codeSent = false;
                              _otpController.clear();
                            }),
                    child: const Text('Use a different email'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// Hub — the groups I'm a member of
// ============================================================
class HubScreen extends StatefulWidget {
  const HubScreen({super.key});

  @override
  State<HubScreen> createState() => _HubScreenState();
}

class _HubScreenState extends State<HubScreen> {
  late Future<List<Map<String, dynamic>>> _groupsFuture;
  String? _displayName;

  @override
  void initState() {
    super.initState();
    _groupsFuture = _loadGroups();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    // fn_my_profile() returns the caller's profile row.
    final rows = await supabase.rpc('fn_my_profile');
    if (rows is List && rows.isNotEmpty && mounted) {
      setState(() => _displayName = rows.first['display_name'] as String?);
    }
  }

  Future<List<Map<String, dynamic>>> _loadGroups() async {
    // RLS on `groups` returns only groups the caller is a member of
    // (plus DISCOVERABLE ones). For the slice that's their groups.
    final rows = await supabase
        .from('groups')
        .select('id, name, description, policy, member_count')
        .order('name');
    return (rows as List).cast<Map<String, dynamic>>();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: _pink,
        foregroundColor: Colors.white,
        title: Text(_displayName == null ? 'My Groups' : 'Hi, $_displayName'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () => supabase.auth.signOut(),
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _groupsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final groups = snapshot.data ?? [];
          if (groups.isEmpty) {
            return const Center(child: Text('You are not in any groups yet.'));
          }
          return RefreshIndicator(
            onRefresh: () async {
              setState(() => _groupsFuture = _loadGroups());
            },
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: groups.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final g = groups[i];
                final desc = (g['description'] ?? '') as String;
                return Card(
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: _pink,
                      child: Text('🍵'),
                    ),
                    title: Text(g['name'] ?? ''),
                    subtitle: Text(
                      '${g['policy']} · ${g['member_count']} members'
                      '${desc.isEmpty ? '' : '\n$desc'}',
                    ),
                    isThreeLine: desc.isNotEmpty,
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => FeedScreen(
                          groupId: g['id'] as String,
                          groupName: g['name'] as String,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

// ============================================================
// Feed — posts in a group (read through posts_feed view)
// ============================================================
class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key, required this.groupId, required this.groupName});

  final String groupId;
  final String groupName;

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  List<Map<String, dynamic>>? _posts; // null = still loading
  Object? _error;
  String? _myAlias; // this user's anonymized alias in this group
  final Set<String> _myUpvotes = {}; // post ids I've upvoted

  @override
  void initState() {
    super.initState();
    _loadPosts();
    _loadMyAlias();
    _loadMyUpvotes();
  }

  Future<void> _loadPosts() async {
    // Direct SELECT on `posts` is revoked by RLS — read the view,
    // which enforces membership and exposes only the alias.
    try {
      final rows = await supabase
          .from('posts_feed')
          .select('id, author_alias, type, body, upvote_count, created_at')
          .eq('group_id', widget.groupId)
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          _posts = (rows as List).cast<Map<String, dynamic>>();
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _loadMyUpvotes() async {
    // post_upvotes SELECT is allowed for group members; filter to mine
    // so we can render the heart filled for posts I've already upvoted.
    final rows = await supabase
        .from('post_upvotes')
        .select('post_id')
        .eq('user_id', supabase.auth.currentUser!.id);
    if (mounted) {
      setState(() {
        _myUpvotes
          ..clear()
          ..addAll((rows as List).map((r) => r['post_id'] as String));
      });
    }
  }

  Future<void> _toggleUpvote(Map<String, dynamic> post) async {
    final postId = post['id'] as String?;
    if (postId == null) return; // optimistic row not reconciled yet
    final wasUpvoted = _myUpvotes.contains(postId);
    final count = (post['upvote_count'] as int?) ?? 0;

    // Optimistic: flip locally first, then let the trigger-maintained
    // count reconcile on the next feed load if anything drifts.
    setState(() {
      if (wasUpvoted) {
        _myUpvotes.remove(postId);
        post['upvote_count'] = count - 1;
      } else {
        _myUpvotes.add(postId);
        post['upvote_count'] = count + 1;
      }
    });

    try {
      if (wasUpvoted) {
        await supabase
            .from('post_upvotes')
            .delete()
            .eq('post_id', postId)
            .eq('user_id', supabase.auth.currentUser!.id);
      } else {
        await supabase.from('post_upvotes').insert({
          'post_id': postId,
          'user_id': supabase.auth.currentUser!.id,
        });
      }
    } catch (e) {
      // Roll back the optimistic change on failure.
      if (mounted) {
        setState(() {
          if (wasUpvoted) {
            _myUpvotes.add(postId);
            post['upvote_count'] = count;
          } else {
            _myUpvotes.remove(postId);
            post['upvote_count'] = count;
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update upvote: $e')),
        );
      }
    }
  }

  Future<void> _loadMyAlias() async {
    // group_memberships SELECT is revoked; read our own alias from
    // the members view (is_me = true) so we can stamp it on new posts.
    final rows = await supabase
        .from('group_members_view')
        .select('alias')
        .eq('group_id', widget.groupId)
        .eq('is_me', true)
        .limit(1);
    if (rows.isNotEmpty && mounted) {
      setState(() => _myAlias = rows.first['alias'] as String?);
    }
  }

  void _openComments(Map<String, dynamic> post) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CommentsScreen(
          postId: post['id'] as String,
          postAlias: (post['author_alias'] as String?) ?? 'anon',
          postBody: post['body'] as String?,
          myAlias: _myAlias,
        ),
      ),
    );
  }

  Future<void> _openComposer() async {
    final alias = _myAlias;
    if (alias == null) return; // still loading membership
    final created = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ComposePostSheet(
        groupId: widget.groupId,
        authorAlias: alias,
      ),
    );
    if (created != null && mounted) {
      // Show it immediately at the top, then reconcile with the view
      // (which fills in the real id / server timestamp / counts).
      setState(() => _posts = [created, ...?_posts]);
      _loadPosts();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: _pink,
        foregroundColor: Colors.white,
        title: Text(widget.groupName),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _pink,
        foregroundColor: Colors.white,
        onPressed: _myAlias == null ? null : _openComposer,
        icon: const Icon(Icons.edit),
        label: const Text('Post'),
      ),
      body: Builder(
        builder: (context) {
          if (_error != null) {
            return Center(child: Text('Error: $_error'));
          }
          final posts = _posts;
          if (posts == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (posts.isEmpty) {
            return const Center(child: Text('No posts yet. Be the first!'));
          }
          return RefreshIndicator(
            onRefresh: _loadPosts,
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: posts.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final p = posts[i];
                final postId = p['id'] as String?;
                final upvoted =
                    postId != null && _myUpvotes.contains(postId);
                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: postId == null ? null : () => _openComments(p),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p['author_alias'] ?? 'anon',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, color: _pink),
                          ),
                          const SizedBox(height: 6),
                          Text(p['body'] ?? '[${p['type']}]'),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                iconSize: 20,
                                color: _pink,
                                tooltip:
                                    upvoted ? 'Remove tea drop' : 'Tea drop',
                                icon: Icon(upvoted
                                    ? Icons.favorite
                                    : Icons.favorite_border),
                                onPressed: postId == null
                                    ? null
                                    : () => _toggleUpvote(p),
                              ),
                              const SizedBox(width: 4),
                              Text('${p['upvote_count']}'),
                              const SizedBox(width: 16),
                              const Icon(Icons.mode_comment_outlined,
                                  size: 18, color: Colors.black45),
                              const SizedBox(width: 4),
                              const Text('Reply',
                                  style: TextStyle(color: Colors.black45)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

// ============================================================
// Compose — write a TEXT post to a group
// ============================================================
class ComposePostSheet extends StatefulWidget {
  const ComposePostSheet({
    super.key,
    required this.groupId,
    required this.authorAlias,
  });

  final String groupId;
  final String authorAlias;

  @override
  State<ComposePostSheet> createState() => _ComposePostSheetState();
}

class _ComposePostSheetState extends State<ComposePostSheet> {
  final _bodyController = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    final body = _bodyController.text.trim();
    if (body.isEmpty) {
      setState(() => _error = 'Write something first.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // RLS "Members can create posts" checks author_user_id = auth.uid()
      // and membership. author_alias is supplied by the client and locked
      // immutable by trigger after insert. We don't chain .select() — SELECT
      // on `posts` is revoked (feed is read via the view) — so we build the
      // optimistic row locally for instant display; _loadPosts reconciles it.
      await supabase.from('posts').insert({
        'group_id': widget.groupId,
        'author_user_id': supabase.auth.currentUser!.id,
        'author_alias': widget.authorAlias,
        'type': 'TEXT',
        'body': body,
      });
      if (mounted) {
        Navigator.of(context).pop(<String, dynamic>{
          'author_alias': widget.authorAlias,
          'type': 'TEXT',
          'body': body,
          'upvote_count': 0,
        });
      }
    } on PostgrestException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text('Posting as ',
                  style: TextStyle(color: Colors.black54)),
              Text(widget.authorAlias,
                  style: const TextStyle(
                      color: _pink, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _bodyController,
            autofocus: true,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(
              hintText: "What's the tea? ☕️",
              border: OutlineInputBorder(),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy ? null : _submit,
            style: FilledButton.styleFrom(backgroundColor: _pink),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: _busy
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Post'),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// Comments — read a post's replies and add TEXT comments
// ============================================================
class CommentsScreen extends StatefulWidget {
  const CommentsScreen({
    super.key,
    required this.postId,
    required this.postAlias,
    required this.postBody,
    required this.myAlias,
  });

  final String postId;
  final String postAlias;
  final String? postBody;
  final String? myAlias; // caller's alias in this group (for new comments)

  @override
  State<CommentsScreen> createState() => _CommentsScreenState();
}

class _CommentsScreenState extends State<CommentsScreen> {
  List<Map<String, dynamic>>? _comments; // flat rows from the view
  Object? _error;
  final _bodyController = TextEditingController();
  final _inputFocus = FocusNode();
  bool _sending = false;

  // When replying to a specific top-level comment, this holds it;
  // null means the new comment is top-level.
  Map<String, dynamic>? _replyingTo;

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  @override
  void dispose() {
    _bodyController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  /// Groups the flat comment rows into top-level comments (in time order)
  /// each followed by its replies (also in time order). Single-level only.
  List<Map<String, dynamic>> _threaded() {
    final all = _comments ?? const [];
    final tops = all.where((c) => c['parent_comment_id'] == null).toList();
    final repliesByParent = <String, List<Map<String, dynamic>>>{};
    for (final c in all) {
      final parent = c['parent_comment_id'] as String?;
      if (parent != null) {
        (repliesByParent[parent] ??= []).add(c);
      }
    }
    final ordered = <Map<String, dynamic>>[];
    for (final t in tops) {
      ordered.add(t);
      final id = t['id'] as String?;
      if (id != null) ordered.addAll(repliesByParent[id] ?? const []);
    }
    return ordered;
  }

  Future<void> _loadComments() async {
    // SELECT on `comments` is revoked — read the comments_feed view,
    // which enforces membership and exposes only the alias.
    try {
      final rows = await supabase
          .from('comments_feed')
          .select('id, parent_comment_id, author_alias, type, body, created_at')
          .eq('post_id', widget.postId)
          .order('created_at', ascending: true);
      if (mounted) {
        setState(() {
          _comments = (rows as List).cast<Map<String, dynamic>>();
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _startReply(Map<String, dynamic> parent) {
    setState(() => _replyingTo = parent);
    _inputFocus.requestFocus();
  }

  void _cancelReply() => setState(() => _replyingTo = null);

  Future<void> _send() async {
    final alias = widget.myAlias;
    final body = _bodyController.text.trim();
    if (alias == null || body.isEmpty || _sending) return;
    // Only top-level comments can be replied to (single-level nesting),
    // so drop any parent that is itself a reply — defensive, the UI only
    // offers Reply on top-level comments.
    final parent = _replyingTo;
    final parentId = (parent != null && parent['parent_comment_id'] == null)
        ? parent['id'] as String?
        : null;
    setState(() => _sending = true);
    try {
      // Same pattern as posts: no chained .select() (SELECT on comments is
      // revoked), so we optimistically append a local row and reconcile.
      await supabase.from('comments').insert({
        'post_id': widget.postId,
        if (parentId != null) 'parent_comment_id': parentId,
        'author_user_id': supabase.auth.currentUser!.id,
        'author_alias': alias,
        'type': 'TEXT',
        'body': body,
      });
      _bodyController.clear();
      if (mounted) {
        setState(() {
          _comments = [
            ...?_comments,
            {
              'author_alias': alias,
              'type': 'TEXT',
              'body': body,
              'parent_comment_id': parentId,
            },
          ];
          _replyingTo = null;
        });
      }
      _loadComments();
    } on PostgrestException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not comment: ${e.message}')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final comments = _comments;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: _pink,
        foregroundColor: Colors.white,
        title: const Text('Comments'),
      ),
      body: Column(
        children: [
          // The post being replied to.
          Container(
            width: double.infinity,
            color: const Color(0xFFFDE7EF),
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.postAlias,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: _pink)),
                const SizedBox(height: 6),
                Text(widget.postBody ?? ''),
              ],
            ),
          ),
          Expanded(
            child: Builder(
              builder: (context) {
                if (_error != null) {
                  return Center(child: Text('Error: $_error'));
                }
                if (comments == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (comments.isEmpty) {
                  return const Center(
                      child: Text('No comments yet. Say something kind 💬'));
                }
                final threaded = _threaded();
                return RefreshIndicator(
                  onRefresh: _loadComments,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: threaded.length,
                    itemBuilder: (context, i) {
                      final c = threaded[i];
                      final isReply = c['parent_comment_id'] != null;
                      final canReply =
                          !isReply && widget.myAlias != null && c['id'] != null;
                      return Padding(
                        padding: EdgeInsets.fromLTRB(
                            isReply ? 36 : 14, 8, 14, 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (isReply)
                              const Padding(
                                padding: EdgeInsets.only(right: 8, top: 2),
                                child: Icon(Icons.subdirectory_arrow_right,
                                    size: 16, color: Colors.black38),
                              ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    c['author_alias'] ?? 'anon',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: _pink),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(c['body'] ?? '[${c['type']}]'),
                                  if (canReply)
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: TextButton(
                                        style: TextButton.styleFrom(
                                          padding: EdgeInsets.zero,
                                          minimumSize: const Size(0, 28),
                                          tapTargetSize: MaterialTapTargetSize
                                              .shrinkWrap,
                                          foregroundColor: Colors.black54,
                                        ),
                                        onPressed: () => _startReply(c),
                                        child: const Text('Reply'),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
          const Divider(height: 1),
          if (_replyingTo != null)
            Container(
              color: const Color(0xFFFDE7EF),
              padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Replying to ${_replyingTo!['author_alias'] ?? 'anon'}',
                      style: const TextStyle(
                          color: _pink, fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close, size: 18),
                    tooltip: 'Cancel reply',
                    onPressed: _cancelReply,
                  ),
                ],
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.only(
                left: 12,
                right: 8,
                top: 8,
                bottom: MediaQuery.of(context).viewInsets.bottom + 8,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _bodyController,
                      focusNode: _inputFocus,
                      minLines: 1,
                      maxLines: 4,
                      enabled: widget.myAlias != null,
                      decoration: InputDecoration(
                        hintText: widget.myAlias == null
                            ? 'Join to comment'
                            : (_replyingTo != null
                                ? 'Write a reply…'
                                : 'Add a comment…'),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  IconButton(
                    color: _pink,
                    icon: _sending
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                    onPressed:
                        widget.myAlias == null || _sending ? null : _send,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
