import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:record/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:video_player/video_player.dart';

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

/// Renders an image stored in the private `post-media` bucket. The bucket
/// is not public, so we mint a short-lived signed URL for the object path
/// (stored in posts.media_url) and load it with Image.network.
class SignedImage extends StatefulWidget {
  const SignedImage({super.key, required this.path});

  final String path; // object path, e.g. "{postId}/photo.jpg"

  @override
  State<SignedImage> createState() => _SignedImageState();
}

class _SignedImageState extends State<SignedImage> {
  late Future<String> _urlFuture;

  @override
  void initState() {
    super.initState();
    _urlFuture = supabase.storage.from('post-media').createSignedUrl(
          widget.path,
          60 * 60, // 1 hour
        );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _urlFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const AspectRatio(
            aspectRatio: 16 / 9,
            child: ColoredBox(
              color: Color(0xFFF0F0F0),
              child: Icon(Icons.broken_image, color: Colors.black26),
            ),
          );
        }
        final url = snapshot.data;
        if (url == null) {
          return const AspectRatio(
            aspectRatio: 16 / 9,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(url, fit: BoxFit.cover),
        );
      },
    );
  }
}

/// Formats a duration in seconds as m:ss (e.g. 83 -> "1:23").
String _fmtDuration(int seconds) {
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// Plays a video stored in the private `post-media` bucket via a signed URL.
/// Shows a tap-to-play overlay; the underlying object path lives in
/// posts.media_url.
class SignedVideo extends StatefulWidget {
  const SignedVideo({super.key, required this.path});

  final String path;

  @override
  State<SignedVideo> createState() => _SignedVideoState();
}

class _SignedVideoState extends State<SignedVideo> {
  VideoPlayerController? _controller;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final url = await supabase.storage
          .from('post-media')
          .createSignedUrl(widget.path, 60 * 60);
      final c = VideoPlayerController.networkUrl(Uri.parse(url));
      await c.initialize();
      c.addListener(() {
        if (mounted) setState(() {});
      });
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() => _controller = c);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return const AspectRatio(
        aspectRatio: 16 / 9,
        child: ColoredBox(
          color: Color(0xFFF0F0F0),
          child: Icon(Icons.broken_image, color: Colors.black26),
        ),
      );
    }
    final c = _controller;
    if (c == null) {
      return const AspectRatio(
        aspectRatio: 16 / 9,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: AspectRatio(
        aspectRatio: c.value.aspectRatio == 0 ? 16 / 9 : c.value.aspectRatio,
        child: Stack(
          alignment: Alignment.center,
          children: [
            VideoPlayer(c),
            // Tap anywhere to toggle play/pause.
            GestureDetector(
              onTap: () {
                setState(() {
                  c.value.isPlaying ? c.pause() : c.play();
                });
              },
              child: AnimatedOpacity(
                opacity: c.value.isPlaying ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  color: Colors.black26,
                  child: const Center(
                    child: Icon(Icons.play_circle_fill,
                        size: 56, color: Colors.white),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Plays a voice recording stored in the private `post-media` bucket via a
/// signed URL. Renders as a compact play/pause pill with the duration.
class SignedAudio extends StatefulWidget {
  const SignedAudio({super.key, required this.path, this.durationSeconds});

  final String path;
  final int? durationSeconds;

  @override
  State<SignedAudio> createState() => _SignedAudioState();
}

class _SignedAudioState extends State<SignedAudio> {
  final _player = AudioPlayer();
  bool _loaded = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final url = await supabase.storage
          .from('post-media')
          .createSignedUrl(widget.path, 60 * 60);
      await _player.setUrl(url);
      if (mounted) setState(() => _loaded = true);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFDE7EF),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_error != null)
            const Icon(Icons.error_outline, color: Colors.black38)
          else if (!_loaded)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            StreamBuilder<PlayerState>(
              stream: _player.playerStateStream,
              builder: (context, snapshot) {
                final playing = snapshot.data?.playing ?? false;
                final completed =
                    snapshot.data?.processingState == ProcessingState.completed;
                final isPlaying = playing && !completed;
                return GestureDetector(
                  onTap: () async {
                    if (isPlaying) {
                      await _player.pause();
                    } else {
                      if (completed) await _player.seek(Duration.zero);
                      await _player.play();
                    }
                  },
                  child: Icon(
                    isPlaying
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_fill,
                    size: 32,
                    color: _pink,
                  ),
                );
              },
            ),
          const SizedBox(width: 8),
          const Icon(Icons.graphic_eq, size: 18, color: _pink),
          if (widget.durationSeconds != null) ...[
            const SizedBox(width: 6),
            Text(_fmtDuration(widget.durationSeconds!),
                style: const TextStyle(color: Colors.black54)),
          ],
        ],
      ),
    );
  }
}

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
          .select(
              'id, author_alias, type, body, media_url, duration_seconds, upvote_count, created_at')
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
                          if (p['media_url'] != null) ...[
                            if (p['type'] == 'IMAGE')
                              SignedImage(path: p['media_url'] as String)
                            else if (p['type'] == 'VIDEO')
                              SignedVideo(path: p['media_url'] as String)
                            else if (p['type'] == 'VOICE')
                              SignedAudio(
                                path: p['media_url'] as String,
                                durationSeconds: p['duration_seconds'] as int?,
                              ),
                            if ((p['body'] as String?)?.isNotEmpty ?? false)
                              const SizedBox(height: 6),
                          ],
                          if ((p['body'] as String?)?.isNotEmpty ?? false)
                            Text(p['body'] as String)
                          else if (p['type'] == 'TEXT')
                            Text('[${p['type']}]'),
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

// What kind of media (if any) is attached to the post being composed.
enum _Media { none, image, video, voice }

class _ComposePostSheetState extends State<ComposePostSheet> {
  final _bodyController = TextEditingController();
  bool _busy = false;
  String? _error;

  // Selected/recorded media. Held as bytes so it works on web and mobile.
  _Media _media = _Media.none;
  Uint8List? _mediaBytes;
  String? _mediaName; // original filename, for extension/content-type
  int? _durationSeconds; // required for VIDEO/VOICE

  // Voice recording state.
  final _recorder = AudioRecorder();
  bool _recording = false;
  int _recordSeconds = 0;
  Timer? _recordTimer;

  static const _maxDurationSeconds = 180; // DB caps VIDEO/VOICE at 180s

  @override
  void dispose() {
    _bodyController.dispose();
    _recordTimer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  void _clearMedia() {
    setState(() {
      _media = _Media.none;
      _mediaBytes = null;
      _mediaName = null;
      _durationSeconds = null;
    });
  }

  Future<void> _pickImage() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 2048,
        imageQuality: 85,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (mounted) {
        setState(() {
          _media = _Media.image;
          _mediaBytes = bytes;
          _mediaName = picked.name;
          _durationSeconds = null;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not pick image: $e');
    }
  }

  Future<void> _pickVideo(ImageSource source) async {
    try {
      final picked = await ImagePicker().pickVideo(
        source: source,
        maxDuration: const Duration(seconds: _maxDurationSeconds),
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();

      // The post-media bucket caps files at 100 MB — fail fast with a clear
      // message rather than erroring out mid-upload.
      if (bytes.lengthInBytes > 100 * 1024 * 1024) {
        if (mounted) {
          setState(() => _error = 'That video is over 100 MB. Pick a shorter '
              'or more compressed clip.');
        }
        return;
      }

      // Probe the real duration — maxDuration isn't enforced when picking an
      // existing file on web, and the DB rejects anything over 180s.
      final seconds = await _probeVideoDuration(bytes, picked.name);
      if (seconds == null) {
        if (mounted) {
          setState(() => _error = "Couldn't read the video's length.");
        }
        return;
      }
      if (seconds > _maxDurationSeconds) {
        if (mounted) {
          setState(() => _error =
              'Videos must be 3 minutes or less (this one is ${_fmtDuration(seconds)}).');
        }
        return;
      }
      if (mounted) {
        setState(() {
          _media = _Media.video;
          _mediaBytes = bytes;
          _mediaName = picked.name;
          _durationSeconds = seconds;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not pick video: $e');
    }
  }

  // Reads a video's duration without uploading it, using an off-screen HTML
  // <video> element pointed at a blob object URL. A blob URL is a short handle
  // the browser streams from memory, so it works for large clips — unlike a
  // base64 data URI, which browsers reject once it's more than a few MB.
  // Returns whole seconds, or null if it can't be read.
  Future<int?> _probeVideoDuration(Uint8List bytes, String name) async {
    final blob = html.Blob([bytes], _videoContentType(name));
    final url = html.Url.createObjectUrlFromBlob(blob);
    final video = html.VideoElement()
      ..preload = 'metadata'
      ..src = url;
    try {
      // Wait for metadata (duration) to load, or bail on error.
      await video.onLoadedMetadata.first
          .timeout(const Duration(seconds: 15));
      final seconds = video.duration; // in fractional seconds
      if (seconds.isNaN || seconds.isInfinite || seconds <= 0) return null;
      // Round up so a 0.4s clip still counts as 1s (DB requires >= 1).
      return seconds.ceil();
    } catch (_) {
      return null;
    } finally {
      video.removeAttribute('src');
      html.Url.revokeObjectUrl(url);
    }
  }

  Future<void> _toggleRecording() async {
    if (_recording) {
      await _stopRecording();
      return;
    }
    try {
      if (!await _recorder.hasPermission()) {
        if (mounted) {
          setState(() => _error = 'Microphone permission is needed to record.');
        }
        return;
      }
      // Web: record to an in-memory stream and get back a blob URL on stop.
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.opus),
        path: '', // ignored on web; a blob URL is returned from stop()
      );
      _recordSeconds = 0;
      _recordTimer =
          Timer.periodic(const Duration(seconds: 1), (t) async {
        if (!mounted) return;
        setState(() => _recordSeconds++);
        if (_recordSeconds >= _maxDurationSeconds) {
          await _stopRecording();
        }
      });
      setState(() {
        _recording = true;
        _media = _Media.voice;
        _mediaBytes = null;
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _recording = false;
          _error = 'Could not start recording: $e';
        });
      }
    }
  }

  Future<void> _stopRecording() async {
    _recordTimer?.cancel();
    _recordTimer = null;
    try {
      final result = await _recorder.stop(); // blob URL (web) or file path
      final seconds = _recordSeconds;
      // record_web returns a blob: URL; fetch it back as bytes.
      final bytes = await _fetchRecordedBytes(result);
      if (bytes == null || seconds < 1) {
        if (mounted) {
          setState(() {
            _recording = false;
            _media = _Media.none;
            _error = 'Recording was too short.';
          });
        }
        return;
      }
      if (mounted) {
        setState(() {
          _recording = false;
          _media = _Media.voice;
          _mediaBytes = bytes;
          _mediaName = 'voice.webm';
          _durationSeconds = seconds;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _recording = false;
          _error = 'Could not finish recording: $e';
        });
      }
    }
  }

  // Fetches bytes from the blob/file URL returned by recorder.stop(). On web
  // this is a `blob:` URL, which the HTTP client can GET in-page.
  Future<Uint8List?> _fetchRecordedBytes(String? url) async {
    if (url == null) return null;
    try {
      final resp = await http.get(Uri.parse(url));
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        return resp.bodyBytes;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  String _videoContentType(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.webm')) return 'video/webm';
    if (n.endsWith('.mov')) return 'video/quicktime';
    return 'video/mp4';
  }

  String _audioContentType(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.mp3')) return 'audio/mpeg';
    if (n.endsWith('.m4a')) return 'audio/mp4';
    if (n.endsWith('.aac')) return 'audio/aac';
    if (n.endsWith('.ogg')) return 'audio/ogg';
    if (n.endsWith('.wav')) return 'audio/wav';
    return 'audio/webm';
  }

  String _imageContentType(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.webp')) return 'image/webp';
    if (n.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }

  // Picked filenames can contain spaces, parentheses, or unicode (e.g.
  // "Screenshot (3).png"), which Supabase Storage rejects with "Invalid
  // key". We only need the extension — the object base name is fixed.
  String _safeExtension(String? name, List<String> allowed, String fallback) {
    final n = (name ?? '').toLowerCase();
    for (final ext in allowed) {
      if (n.endsWith('.$ext')) return ext;
    }
    return fallback;
  }

  Future<void> _submit() async {
    final body = _bodyController.text.trim();
    final bytes = _mediaBytes;
    final hasMedia = _media != _Media.none && bytes != null;

    if (body.isEmpty && !hasMedia) {
      setState(() => _error = 'Write something or add media.');
      return;
    }
    if (_recording) {
      setState(() => _error = 'Stop the recording first.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });

    final uid = supabase.auth.currentUser!.id;

    try {
      if (!hasMedia) {
        // Plain TEXT post.
        await supabase.from('posts').insert({
          'group_id': widget.groupId,
          'author_user_id': uid,
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
        return;
      }

      // Media post. Storage RLS resolves the group from the postId in the
      // object path, so the post row must exist before the upload; the
      // media_url CHECK also requires a URL at insert time. Generate the id
      // client-side and set media_url to the path we're about to write.
      final postId = const Uuid().v4();
      final String type;
      final String fileName;
      final String contentType;
      switch (_media) {
        case _Media.image:
          type = 'IMAGE';
          fileName =
              'photo.${_safeExtension(_mediaName, const ['png', 'webp', 'gif', 'jpeg', 'jpg'], 'jpg')}';
          contentType = _imageContentType(fileName);
        case _Media.video:
          type = 'VIDEO';
          fileName =
              'video.${_safeExtension(_mediaName, const ['mp4', 'webm', 'mov'], 'mp4')}';
          contentType = _videoContentType(fileName);
        case _Media.voice:
          type = 'VOICE';
          fileName =
              'voice.${_safeExtension(_mediaName, const ['webm', 'm4a', 'mp3', 'aac', 'ogg', 'wav'], 'webm')}';
          contentType = _audioContentType(fileName);
        case _Media.none:
          return; // unreachable — guarded by hasMedia
      }
      final path = '$postId/$fileName';
      final isTimed = _media == _Media.video || _media == _Media.voice;

      await supabase.from('posts').insert({
        'id': postId,
        'group_id': widget.groupId,
        'author_user_id': uid,
        'author_alias': widget.authorAlias,
        'type': type,
        'media_url': path,
        if (isTimed) 'duration_seconds': _durationSeconds,
        if (body.isNotEmpty) 'body': body,
      });

      await supabase.storage.from('post-media').uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: contentType),
          );

      if (mounted) {
        Navigator.of(context).pop(<String, dynamic>{
          'id': postId,
          'author_alias': widget.authorAlias,
          'type': type,
          'body': body,
          'media_url': path,
          if (isTimed) 'duration_seconds': _durationSeconds,
          'upvote_count': 0,
        });
      }
    } on PostgrestException catch (e) {
      setState(() => _error = e.message);
    } on StorageException catch (e) {
      setState(() => _error = 'Upload failed: ${e.message}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // Small pink circle "remove" button shown on media previews.
  Widget _removeMediaButton() {
    return Padding(
      padding: const EdgeInsets.all(4),
      child: CircleAvatar(
        backgroundColor: Colors.black54,
        radius: 16,
        child: IconButton(
          icon: const Icon(Icons.close, size: 16, color: Colors.white),
          tooltip: 'Remove',
          onPressed: _busy ? null : _clearMedia,
        ),
      ),
    );
  }

  Widget _mediaPreview() {
    final bytes = _mediaBytes;
    switch (_media) {
      case _Media.image:
        if (bytes == null) return const SizedBox.shrink();
        return Stack(
          alignment: Alignment.topRight,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(bytes,
                  height: 180, width: double.infinity, fit: BoxFit.cover),
            ),
            _removeMediaButton(),
          ],
        );
      case _Media.video:
        return Stack(
          alignment: Alignment.topRight,
          children: [
            Container(
              height: 120,
              decoration: BoxDecoration(
                color: const Color(0xFFEDEDED),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.movie_outlined, color: _pink),
                    const SizedBox(width: 8),
                    Text('Video ready'
                        '${_durationSeconds != null ? ' · ${_fmtDuration(_durationSeconds!)}' : ''}',
                        style: const TextStyle(color: Colors.black54)),
                  ],
                ),
              ),
            ),
            _removeMediaButton(),
          ],
        );
      case _Media.voice:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFFDE7EF),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              if (_recording) ...[
                const Icon(Icons.fiber_manual_record,
                    color: Colors.red, size: 16),
                const SizedBox(width: 8),
                Text('Recording… ${_fmtDuration(_recordSeconds)}',
                    style: const TextStyle(color: Colors.black87)),
                const Spacer(),
                TextButton.icon(
                  onPressed: _stopRecording,
                  icon: const Icon(Icons.stop_circle, color: _pink),
                  label: const Text('Stop'),
                ),
              ] else ...[
                const Icon(Icons.graphic_eq, color: _pink),
                const SizedBox(width: 8),
                Text('Voice note'
                    '${_durationSeconds != null ? ' · ${_fmtDuration(_durationSeconds!)}' : ''}',
                    style: const TextStyle(color: Colors.black87)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.black54),
                  tooltip: 'Remove',
                  onPressed: _busy ? null : _clearMedia,
                ),
              ],
            ],
          ),
        );
      case _Media.none:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasMedia = _media != _Media.none;
    // Only offer the media toolbar when nothing is attached yet — one media
    // item per post (matches the schema: no mixing media types).
    final showToolbar = !hasMedia && !_recording;
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
          if (hasMedia || _recording) ...[
            _mediaPreview(),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _bodyController,
            autofocus: true,
            minLines: 3,
            maxLines: 6,
            decoration: InputDecoration(
              hintText: hasMedia ? 'Add a caption…' : "What's the tea? ☕️",
              border: const OutlineInputBorder(),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              if (showToolbar) ...[
                IconButton(
                  onPressed: _busy ? null : _pickImage,
                  icon: const Icon(Icons.image_outlined),
                  color: _pink,
                  tooltip: 'Add photo',
                ),
                IconButton(
                  onPressed: _busy ? null : () => _pickVideoMenu(context),
                  icon: const Icon(Icons.videocam_outlined),
                  color: _pink,
                  tooltip: 'Add video',
                ),
                IconButton(
                  onPressed: _busy ? null : _toggleRecording,
                  icon: const Icon(Icons.mic_none),
                  color: _pink,
                  tooltip: 'Record voice',
                ),
              ],
              const Spacer(),
              Expanded(
                child: FilledButton(
                  onPressed: (_busy || _recording) ? null : _submit,
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
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Video can come from an existing file or (where supported) the camera.
  Future<void> _pickVideoMenu(BuildContext context) async {
    final choice = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.video_library_outlined, color: _pink),
              title: const Text('Choose a video'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined, color: _pink),
              title: const Text('Record a video'),
              subtitle: const Text('Uses your camera where supported'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (choice != null) await _pickVideo(choice);
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
