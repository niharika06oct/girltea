import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart' hide Config;
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:record/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:video_player/video_player.dart';

import 'config.dart';
import 'design/tokens.dart';
import 'design/type.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: Config.supabaseUrl,
    anonKey: Config.supabaseAnonKey,
  );
  runApp(const GirlTeaApp());
}

final supabase = Supabase.instance.client;

/// Header face helper. Poppins is dropped (mockup = Playfair + Inter only);
/// headers now use Playfair Display. Kept as a thin wrapper so existing
/// header call-sites stay short while they migrate to [GtText].
TextStyle _headerFont({
  required double size,
  Color? color,
  FontWeight weight = FontWeight.w600,
}) =>
    GoogleFonts.playfairDisplay(fontSize: size, color: color, fontWeight: weight);

/// The GirlTea wordmark in Playfair Display (the mockup's "Accents" face),
/// with the little teacup. Used on the login screen and the top bar.
class GirlTeaWordmark extends StatelessWidget {
  const GirlTeaWordmark({super.key, this.fontSize = 22, this.center = false});

  final double fontSize;
  final bool center;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment:
          center ? MainAxisAlignment.center : MainAxisAlignment.start,
      children: [
        Text(
          'GirlTea',
          style: GoogleFonts.playfairDisplay(
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
            color: context.gt.brand,
          ),
        ),
        SizedBox(width: fontSize * 0.35),
        Text('🍵', style: TextStyle(fontSize: fontSize * 0.9)),
      ],
    );
  }
}

// ============================================================
// Theme controller — the member's chosen app-wide theme
// ============================================================
// The profile menu lets you pick a vibe (Cotton Candy, Indigo Nights, …);
// we persist the choice in the browser so it survives a refresh. A global
// ChangeNotifier drives MaterialApp.router's theme. Each theme carries its own
// brightness, so the two dark themes replace the old light/dark toggle.
class ThemeController extends ChangeNotifier {
  GtTheme _theme = gtThemeByName(html.window.localStorage[_storageKey]);
  GtTheme get theme => _theme;

  static const _storageKey = 'girltea_theme';

  void set(GtThemeId id) {
    if (id == _theme.id) return;
    _theme = gtThemeByName(id.name);
    html.window.localStorage[_storageKey] = id.name;
    notifyListeners();
  }
}

final themeController = ThemeController();

// Bumped whenever a post is created from the global "Spill" button so the
// currently-visible feed (only one is mounted at a time) reloads itself.
final feedRefresh = ValueNotifier<int>(0);

/// Opens the composer for [groupId] from anywhere (e.g. the top-bar Spill
/// button), loading the caller's per-group alias first. On success it signals
/// the visible feed to reload via [feedRefresh].
Future<void> spillInto(BuildContext context, String groupId) async {
  String? alias;
  try {
    final rows = await supabase
        .from('group_members_view')
        .select('alias')
        .eq('group_id', groupId)
        .eq('is_me', true)
        .limit(1);
    if (rows.isNotEmpty) alias = rows.first['alias'] as String?;
  } catch (_) {
    // fall through — handled below
  }
  if (alias == null || !context.mounted) return;
  final created = await showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    builder: (_) => ComposePostSheet(groupId: groupId, authorAlias: alias!),
  );
  if (created != null) feedRefresh.value++;
}

// ============================================================
// Groups controller — one shared load of the user's circles
// ============================================================
// The rail, the overview and the feed all need the same list of circles
// (and the ability to resolve a slug -> group). Loading it once here and
// sharing it via an InheritedNotifier keeps every pane in sync and lets a
// deep link (/college-girls) resolve without each screen re-fetching.
class GroupsController extends ChangeNotifier {
  List<Map<String, dynamic>>? groups; // null = not loaded yet
  Object? error;
  String? displayName;
  String? gender; // the caller's stored gender enum, null = prefer not to say

  /// Whether we've resolved the caller's profile row yet, and whether it
  /// exists. A signed-in user has an auth account but no `users` row until
  /// they complete onboarding — and creating/joining circles requires one.
  bool profileLoaded = false;
  bool hasProfile = false;

  bool _loading = false;

  Future<void> ensureLoaded() async {
    if (groups != null || _loading) return;
    await refresh();
  }

  Future<void> refresh() async {
    _loading = true;
    try {
      final rows = await supabase
          .from('groups')
          .select('id, name, slug, description, policy, member_count')
          .order('name');
      groups = (rows as List).cast<Map<String, dynamic>>();
      error = null;
    } catch (e) {
      error = e;
    } finally {
      _loading = false;
      notifyListeners();
    }
    // Profile name is best-effort and independent of the groups load.
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final rows = await supabase.rpc('fn_my_profile');
      if (rows is List && rows.isNotEmpty) {
        displayName = rows.first['display_name'] as String?;
        gender = rows.first['gender'] as String?;
        hasProfile = true;
      } else {
        hasProfile = false;
      }
    } catch (_) {
      // Non-fatal.
    } finally {
      profileLoaded = true;
      notifyListeners();
    }
  }

  /// Clears cached state on sign-out so the next user starts clean.
  void reset() {
    groups = null;
    error = null;
    displayName = null;
    gender = null;
    profileLoaded = false;
    hasProfile = false;
    notifyListeners();
  }

  Map<String, dynamic>? bySlug(String slug) {
    for (final g in groups ?? const []) {
      if (g['slug'] == slug) return g;
    }
    return null;
  }
}

final groupsController = GroupsController();

/// Exposes [GroupsController] to the widget tree and rebuilds dependents
/// when it notifies.
class GroupsScope extends InheritedNotifier<GroupsController> {
  GroupsScope({super.key, required super.child})
      : super(notifier: groupsController);

  static GroupsController of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<GroupsScope>();
    return scope!.notifier!;
  }
}

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
          return AspectRatio(
            aspectRatio: 16 / 9,
            child: ColoredBox(
              color: context.gt.surfaceSunken,
              child: Icon(Icons.broken_image, color: context.gt.onSurfaceFaint),
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

/// Compact "time ago" for the post context line (e.g. "3h", "2d", "just now").
/// Takes an ISO-8601 timestamp; returns '' if it can't be parsed.
String _timeAgo(String? iso) {
  if (iso == null) return '';
  final t = DateTime.tryParse(iso);
  if (t == null) return '';
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 60) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  if (d.inDays < 7) return '${d.inDays}d ago';
  if (d.inDays < 30) return '${(d.inDays / 7).floor()}w ago';
  if (d.inDays < 365) return '${(d.inDays / 30).floor()}mo ago';
  return '${(d.inDays / 365).floor()}y ago';
}

/// The short id used in post URLs (/:slug/:shortId): the first 8 chars of the
/// post UUID. Long enough to be unique within a single circle's feed, short
/// enough to keep the URL tidy. Resolved back to the full row by prefix match.
String _postShortId(String postId) =>
    postId.length <= 8 ? postId : postId.substring(0, 8);

/// A little emoji + deterministic tint for a circle avatar, derived from the
/// group id so each circle keeps a stable look without any stored asset.
({String emoji, Color color}) _circleGlyph(String id) {
  const emojis = ['👭', '💍', '🏋️', '✍️', '🎨', '🌙', '☕', '🌸', '🎧', '📚'];
  const colors = [
    Color(0xFFD6336C), // pink
    Color(0xFF7048E8), // violet
    Color(0xFF1098AD), // teal
    Color(0xFFE8590C), // orange
    Color(0xFF2F9E44), // green
    Color(0xFFE64980), // magenta
  ];
  var h = 0;
  for (final c in id.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return (emoji: emojis[h % emojis.length], color: colors[h % colors.length]);
}

// ============================================================
// Reporting — reason enum labels + a shared report flow
// ============================================================
// Keys are the report_reason enum values; values are human labels.
const Map<String, String> _reportReasons = {
  'HARASSMENT': 'Harassment or bullying',
  'HATE_SPEECH': 'Hate speech',
  'VIOLENCE_OR_THREAT': 'Violence or threats',
  'SEXUAL_CONTENT': 'Unwanted sexual content',
  'CSAM': 'Child sexual abuse material',
  'NON_CONSENSUAL_IMAGERY': 'Non-consensual imagery',
  'SELF_HARM': 'Self-harm',
  'SPAM': 'Spam',
  'MISINFORMATION': 'Misinformation',
  'PRIVACY_VIOLATION': 'Privacy violation',
  'IMPERSONATION': 'Impersonation',
  'DEFAMATION': 'Defamation',
  'OTHER': 'Something else',
};

/// Opens the report sheet for a POST or COMMENT and files it via
/// fn_submit_report (which snapshots evidence server-side). Shows a
/// confirmation or error snackbar. targetType is 'POST' or 'COMMENT'.
Future<void> showReportSheet(
  BuildContext context, {
  required String targetType,
  required String targetId,
}) async {
  final result = await showModalBottomSheet<({String reason, String? details})>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ReportSheet(targetLabel: targetType.toLowerCase()),
  );
  if (result == null) return;
  try {
    await supabase.rpc('fn_submit_report', params: {
      'p_target_type': targetType,
      'p_target_id': targetId,
      'p_reason': result.reason,
      'p_details': result.details,
    });
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thanks — a moderator will review this.')),
      );
    }
  } on PostgrestException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not report: ${e.message}')),
      );
    }
  }
}

class _ReportSheet extends StatefulWidget {
  const _ReportSheet({required this.targetLabel});

  final String targetLabel; // "post" / "comment"

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  String? _reason;
  final _detailsController = TextEditingController();

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
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
          Text('Report this ${widget.targetLabel}',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('Your report is anonymous to other members.',
              style: TextStyle(color: context.gt.onSurfaceMuted)),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final entry in _reportReasons.entries)
                    RadioListTile<String>(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      activeColor: context.gt.accent,
                      value: entry.key,
                      groupValue: _reason,
                      title: Text(entry.value),
                      onChanged: (v) => setState(() => _reason = v),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _detailsController,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Add details (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: context.gt.accent),
            onPressed: _reason == null
                ? null
                : () {
                    final details = _detailsController.text.trim();
                    Navigator.of(context).pop((
                      reason: _reason!,
                      details: details.isEmpty ? null : details,
                    ));
                  },
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Submit report'),
            ),
          ),
        ],
      ),
    );
  }
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
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: ColoredBox(
          color: context.gt.surfaceSunken,
          child: Icon(Icons.broken_image, color: context.gt.onSurfaceFaint),
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
        color: context.gt.accentSoft,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_error != null)
            Icon(Icons.error_outline, color: context.gt.onSurfaceFaint)
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
                    color: context.gt.accent,
                  ),
                );
              },
            ),
          const SizedBox(width: 8),
          Icon(Icons.graphic_eq, size: 18, color: context.gt.accent),
          if (widget.durationSeconds != null) ...[
            const SizedBox(width: 6),
            Text(_fmtDuration(widget.durationSeconds!),
                style: TextStyle(color: context.gt.onSurfaceMuted)),
          ],
        ],
      ),
    );
  }
}

/// Builds the app theme for a brightness entirely from design tokens
/// (design/tokens.dart + design/type.dart). Every Material surface — cards,
/// chips, app bar, sheets, dividers, nav bar, snack bars, inputs, buttons —
/// is themed from the same semantic [GtColors], so generic Material chrome
/// disappears and dark mode is a pure token swap. Read colours at call-sites
/// via `context.gt.*`, never inline hex.
ThemeData _buildTheme(GtColors gt, Brightness brightness) {
  final isLight = brightness == Brightness.light;

  final scheme = ColorScheme(
    brightness: brightness,
    primary: gt.accent,
    onPrimary: gt.onAccent,
    primaryContainer: gt.accentSoft,
    onPrimaryContainer: gt.onSurface,
    secondary: gt.lavender,
    onSecondary: gt.onSurface,
    secondaryContainer: gt.accentSoft,
    onSecondaryContainer: gt.onSurface,
    tertiary: gt.teaBrown,
    onTertiary: Colors.white,
    error: gt.danger,
    onError: isLight ? Colors.white : const Color(0xFF3A0A08),
    surface: gt.surface,
    onSurface: gt.onSurface,
    surfaceContainerLowest: gt.surfaceSunken,
    surfaceContainerLow: gt.surface,
    surfaceContainer: gt.surfaceRaised,
    surfaceContainerHigh: gt.surfaceRaised,
    surfaceContainerHighest: gt.surfaceRaised,
    onSurfaceVariant: gt.onSurfaceMuted,
    outline: gt.hairline,
    outlineVariant: gt.hairline,
    shadow: Colors.black,
  );

  final base = ThemeData(colorScheme: scheme, useMaterial3: true);
  final textTheme = gtTextTheme(gt.onSurface, gt.onSurfaceMuted);

  OutlineInputBorder inputBorder(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: GtRadii.all(GtRadii.md),
        borderSide: BorderSide(color: c, width: w),
      );

  return base.copyWith(
    scaffoldBackgroundColor: gt.surface,
    canvasColor: gt.surface,
    dividerColor: gt.hairline,
    textTheme: textTheme,
    extensions: [gt],
    appBarTheme: AppBarTheme(
      backgroundColor: gt.surface,
      foregroundColor: gt.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: GtText.title(color: gt.onSurface),
    ),
    cardTheme: CardThemeData(
      color: gt.surfaceRaised,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: GtRadii.all(GtRadii.lg),
        side: BorderSide(color: gt.hairline),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: gt.surfaceSunken,
      selectedColor: gt.accentSoft,
      disabledColor: gt.surfaceSunken,
      side: BorderSide(color: gt.hairline),
      labelStyle: GtText.label(color: gt.onSurface),
      secondaryLabelStyle: GtText.label(color: gt.accent),
      shape: RoundedRectangleBorder(borderRadius: GtRadii.all(GtRadii.pill)),
      padding: const EdgeInsets.symmetric(
          horizontal: GtSpace.md, vertical: GtSpace.xs),
    ),
    dividerTheme: DividerThemeData(
      color: gt.hairline,
      thickness: 1,
      space: GtSpace.lg,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: gt.surfaceRaised,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: gt.surfaceRaised,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(GtRadii.xl)),
      ),
      showDragHandle: true,
      dragHandleColor: gt.hairline,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: gt.surfaceRaised,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: GtRadii.all(GtRadii.xl)),
      titleTextStyle: GtText.title(color: gt.onSurface),
      contentTextStyle: GtText.body(color: gt.onSurface),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: gt.surfaceRaised,
      surfaceTintColor: Colors.transparent,
      indicatorColor: gt.accentSoft,
      elevation: 0,
      height: 68,
      labelTextStyle: WidgetStateProperty.all(GtText.overline(color: gt.onSurfaceMuted)),
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? gt.accent
                : gt.onSurfaceMuted,
          )),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: gt.onSurface,
      contentTextStyle: GtText.body(color: gt.surface),
      actionTextColor: gt.accent,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: GtRadii.all(GtRadii.md)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: gt.accent,
        foregroundColor: gt.onAccent,
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: GtSpace.xl),
        shape: RoundedRectangleBorder(borderRadius: GtRadii.all(GtRadii.pill)),
        textStyle: GtText.label(),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: gt.accent,
        textStyle: GtText.label(),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: gt.accent,
        minimumSize: const Size(0, 48),
        side: BorderSide(color: gt.hairline),
        shape: RoundedRectangleBorder(borderRadius: GtRadii.all(GtRadii.pill)),
        textStyle: GtText.label(),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: gt.onSurfaceMuted),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: gt.accent,
      foregroundColor: gt.onAccent,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: GtRadii.all(GtRadii.lg)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: gt.surfaceRaised,
      hintStyle: GtText.body(color: gt.onSurfaceFaint),
      labelStyle: GtText.body(color: gt.onSurfaceMuted),
      contentPadding: const EdgeInsets.symmetric(
          horizontal: GtSpace.lg, vertical: GtSpace.md),
      border: inputBorder(gt.hairline),
      enabledBorder: inputBorder(gt.hairline),
      focusedBorder: inputBorder(gt.accent, 1.6),
      errorBorder: inputBorder(gt.danger),
      focusedErrorBorder: inputBorder(gt.danger, 1.6),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: gt.onSurfaceMuted,
      textColor: gt.onSurface,
    ),
    iconTheme: IconThemeData(color: gt.onSurfaceMuted),
    tabBarTheme: TabBarThemeData(
      labelColor: gt.accent,
      unselectedLabelColor: gt.onSurfaceMuted,
      indicatorColor: gt.accent,
      labelStyle: GtText.label(),
      unselectedLabelStyle: GtText.label(),
      dividerColor: Colors.transparent,
    ),
  );
}

class GirlTeaApp extends StatelessWidget {
  const GirlTeaApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Rebuild the whole app when the chosen theme changes. Each theme carries
    // its own brightness, so we build one ThemeData from it and pin themeMode
    // to that brightness (theme == darkTheme keeps either mode identical).
    return AnimatedBuilder(
      animation: themeController,
      builder: (context, _) {
        final t = themeController.theme;
        final built = _buildTheme(t.colors, t.brightness);
        return MaterialApp.router(
          title: 'GirlTea',
          debugShowCheckedModeBanner: false,
          theme: built,
          darkTheme: built,
          themeMode: t.isDark ? ThemeMode.dark : ThemeMode.light,
          routerConfig: _router,
          // Shared groups cache lives above every route so the shell and panes
          // can read/resolve slugs from one place.
          builder: (context, child) =>
              GroupsScope(child: child ?? const SizedBox()),
        );
      },
    );
  }
}

// ============================================================
// Routing
// ============================================================
// Real URLs so pages are bookmarkable / shareable / refreshable:
//   /login                      — signed out
//   /home                       — all your circles (overview)
//   /:groupSlug                 — one circle's feed
//   /:groupSlug/:postId         — a single post + its tea
//
// A ShellRoute keeps the desktop chrome (left rail, right panel) mounted
// across circle/post navigation. Auth redirects bounce between /login and
// /home based on the session; `refreshListenable` re-runs the redirect on
// every auth state change.

/// Bridges Supabase's auth stream to a Listenable go_router can watch.
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh() {
    _sub = supabase.auth.onAuthStateChange.listen((_) {
      // Drop cached circles when the session flips (sign in/out).
      if (supabase.auth.currentSession == null) groupsController.reset();
      notifyListeners();
    });
  }
  late final StreamSubscription<AuthState> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

final _authRefresh = _AuthRefresh();

/// Stashes an invite token while a signed-out visitor is bounced through
/// login/onboarding, so opening `/join/<token>` still lands them on the right
/// circle once they have an account.
const _pendingInviteKey = 'girltea_pending_invite';

final _router = GoRouter(
  initialLocation: '/home',
  refreshListenable: _authRefresh,
  redirect: (context, state) {
    final signedIn = supabase.auth.currentSession != null;
    final path = state.uri.path;
    final atLogin = path == '/login';
    final atJoin = path.startsWith('/join/');
    if (!signedIn) {
      // Remember the invite so we can resume after they sign in / onboard.
      if (atJoin) {
        html.window.localStorage[_pendingInviteKey] =
            path.substring('/join/'.length);
      }
      return atLogin ? null : '/login';
    }
    if (atLogin) {
      final pending = html.window.localStorage[_pendingInviteKey];
      if (pending != null && pending.isNotEmpty) return '/join/$pending';
      return '/home';
    }
    return null;
  },
  routes: [
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/join/:token',
      builder: (context, state) =>
          InviteLandingScreen(token: state.pathParameters['token']!),
    ),
    ShellRoute(
      builder: (context, state, child) => HomeShell(state: state, child: child),
      routes: [
        GoRoute(
          path: '/home',
          builder: (context, state) => const _OverviewPane(),
        ),
        GoRoute(
          path: '/me',
          builder: (context, state) => const ProfileScreen(),
        ),
        GoRoute(
          path: '/:groupSlug',
          builder: (context, state) => _FeedPane(
            slug: state.pathParameters['groupSlug']!,
          ),
          routes: [
            GoRoute(
              path: ':postId',
              builder: (context, state) => _PostPane(
                slug: state.pathParameters['groupSlug']!,
                postId: state.pathParameters['postId']!,
              ),
            ),
          ],
        ),
      ],
    ),
  ],
);

// ============================================================
// Login — email OTP (local codes arrive in Mailpit :54324)
// ============================================================
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
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
                const GirlTeaWordmark(fontSize: 40, center: true),
                const SizedBox(height: 8),
                Text(
                  'Vent. Support. Spill the tea.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: context.gt.onSurfaceMuted),
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _emailController,
                  enabled: !_codeSent,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    hintText: 'you@example.com',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_codeSent) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _otpController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Enter your login code',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: context.gt.danger)),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : (_codeSent ? _verify : _sendCode),
                  style: FilledButton.styleFrom(backgroundColor: context.gt.accent),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: _busy
                        ? SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: context.gt.onAccent),
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
// Home shell — persistent chrome around the routed panes
// ============================================================
// On wide screens: left circle rail | routed child | (extra-wide) circle
// panel, all kept mounted across navigation. On narrow screens: just the
// routed child (the panes render their own mobile chrome). Loads the shared
// GroupsController once so a deep link like /college-girls can resolve.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.state, required this.child});

  final GoRouterState state;
  final Widget child;

  // Width at/above which we show the three-pane desktop shell.
  static const double wideBreakpoint = 900;
  // Width at/above which we also show the right-hand circle panel.
  static const double panelBreakpoint = 1180;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  @override
  void initState() {
    super.initState();
    // Kick off the shared load (no-op if already loaded).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      groupsController.ensureLoaded();
    });
  }

  // The slug in the current URL, if we're inside a circle (/:slug[/:post]).
  String? get _currentSlug {
    final segs = widget.state.uri.pathSegments;
    if (segs.isEmpty) return null;
    const nonCircle = {'home', 'login', 'me'};
    if (nonCircle.contains(segs.first)) return null;
    return segs.first;
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild when the shared controller updates (groups loaded, etc.).
    final gc = GroupsScope.of(context);
    final slug = _currentSlug;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= HomeShell.wideBreakpoint;
        if (!wide) {
          // Mobile: global top bar, then the routed pane fills the rest.
          return Scaffold(
            appBar: _TopBar(currentSlug: slug, dense: true),
            body: ShellLayout(embedded: true, child: widget.child),
          );
        }
        final showPanel = constraints.maxWidth >= HomeShell.panelBreakpoint;
        final selected = slug == null ? null : gc.bySlug(slug);
        return Scaffold(
          appBar: _TopBar(currentSlug: slug),
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _CircleRail(
                groups: gc.groups,
                error: gc.error,
                selectedSlug: slug,
                displayName: gc.displayName,
                onSelect: (s) => context.go('/$s'),
              ),
              VerticalDivider(width: 1, color: context.gt.hairline),
              Expanded(
                child: ShellLayout(embedded: true, child: widget.child),
              ),
              if (showPanel && selected != null) ...[
                VerticalDivider(width: 1, color: context.gt.hairline),
                _CirclePanel(
                  key: ValueKey('panel-${selected['id']}'),
                  group: selected,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ============================================================
// Top bar — brand (left) · Spill (center) · profile menu (right)
// ============================================================
// A single global bar across every signed-in screen. Tapping the brand goes
// home; the centered Spill button composes into the current circle (disabled
// on /home where there's no circle context); the right-corner avatar opens a
// Reddit-style menu: View Profile, Theme, Log Out.
class _TopBar extends StatelessWidget implements PreferredSizeWidget {
  const _TopBar({required this.currentSlug, this.dense = false});

  /// Slug of the circle currently in view, or null on /home.
  final String? currentSlug;
  final bool dense;

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    final gc = GroupsScope.of(context);
    final group = currentSlug == null ? null : gc.bySlug(currentSlug!);
    final theme = Theme.of(context);
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.4)),
        ),
      ),
      padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 16),
      child: Row(
        children: [
          // Brand → home.
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => context.go('/home'),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: GirlTeaWordmark(fontSize: 22),
            ),
          ),
          // Centered Spill.
          Expanded(
            child: Center(
              child: FilledButton.icon(
                onPressed: group == null
                    ? null
                    : () => spillInto(context, group['id'] as String),
                style: FilledButton.styleFrom(backgroundColor: context.gt.accent),
                icon: const Icon(Icons.edit, size: 18),
                label: const Text('Spill'),
              ),
            ),
          ),
          _ProfileMenu(displayName: gc.displayName),
        ],
      ),
    );
  }
}

/// The right-corner avatar + dropdown: View Profile, Theme, Log Out.
class _ProfileMenu extends StatelessWidget {
  const _ProfileMenu({required this.displayName});

  final String? displayName;

  @override
  Widget build(BuildContext context) {
    final name = displayName ?? 'you';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '🙂';
    return PopupMenuButton<String>(
      tooltip: 'Account',
      offset: const Offset(0, 48),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      onSelected: (v) {
        switch (v) {
          case 'profile':
            context.go('/me');
          case 'display':
            _showThemeSheet(context);
          case 'logout':
            supabase.auth.signOut();
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'profile',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              backgroundColor: context.gt.accent,
              child: Text(initial,
                  style: TextStyle(color: context.gt.onAccent)),
            ),
            title: const Text('View Profile'),
            subtitle: Text(name, overflow: TextOverflow.ellipsis),
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'display',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.palette_outlined),
            title: Text('Theme'),
          ),
        ),
        const PopupMenuItem(
          value: 'logout',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.logout),
            title: Text('Log Out'),
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: CircleAvatar(
          radius: 18,
          backgroundColor: context.gt.accent,
          child: Text(initial,
              style: TextStyle(
                  color: context.gt.onAccent, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }
}

/// Bottom sheet to pick the app-wide theme ("be you, here"). Each row is a
/// full vibe: emoji + name + tagline + a preview of the palette. Tapping one
/// applies it immediately and persists the choice.
void _showThemeSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) {
      return AnimatedBuilder(
        animation: themeController,
        builder: (context, _) {
          final gt = context.gt;
          final selectedId = themeController.theme.id;

          Widget swatchRow(GtTheme theme) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final c in theme.swatches)
                    Container(
                      width: 16,
                      height: 16,
                      margin: const EdgeInsets.only(right: 4),
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(color: gt.hairline),
                      ),
                    ),
                ],
              );

          Widget card(GtTheme theme) {
            final selected = theme.id == selectedId;
            return Padding(
              padding: const EdgeInsets.fromLTRB(
                  GtSpace.lg, 0, GtSpace.lg, GtSpace.sm),
              child: Material(
                color: selected ? gt.accentSoft : gt.surfaceRaised,
                borderRadius: GtRadii.all(GtRadii.lg),
                child: InkWell(
                  borderRadius: GtRadii.all(GtRadii.lg),
                  onTap: () {
                    themeController.set(theme.id);
                    Navigator.of(sheetContext).pop();
                  },
                  child: Container(
                    padding: const EdgeInsets.all(GtSpace.md),
                    decoration: BoxDecoration(
                      borderRadius: GtRadii.all(GtRadii.lg),
                      border: Border.all(
                        color: selected ? gt.accent : gt.hairline,
                        width: selected ? 1.6 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(theme.emoji,
                            style: const TextStyle(fontSize: 22)),
                        const SizedBox(width: GtSpace.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(theme.name,
                                      style: GtText.titleUi(color: gt.onSurface)),
                                  if (theme.isDark) ...[
                                    const SizedBox(width: GtSpace.sm),
                                    Icon(Icons.dark_mode_outlined,
                                        size: 14, color: gt.onSurfaceFaint),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(theme.tagline,
                                  style: GtText.bodySm(
                                      color: gt.onSurfaceMuted)),
                              const SizedBox(height: GtSpace.sm),
                              swatchRow(theme),
                            ],
                          ),
                        ),
                        const SizedBox(width: GtSpace.sm),
                        Icon(
                          selected
                              ? Icons.check_circle
                              : Icons.circle_outlined,
                          color: selected ? gt.accent : gt.onSurfaceFaint,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }

          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.8,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        GtSpace.xl, GtSpace.lg, GtSpace.xl, GtSpace.xs),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Theme',
                              style: GtText.title(color: gt.onSurface)),
                          Text('Different vibes, same safe space. Be you, here.',
                              style: GtText.bodySm(color: gt.onSurfaceMuted)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: GtSpace.sm),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [for (final t in gtThemes) card(t)],
                    ),
                  ),
                  const SizedBox(height: GtSpace.sm),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

/// Tells the routed panes whether they're rendered inside the desktop shell
/// (embedded, no own Scaffold/AppBar) or standalone on mobile.
class ShellLayout extends InheritedWidget {
  const ShellLayout({super.key, required this.embedded, required super.child});

  final bool embedded;

  static bool embeddedOf(BuildContext context) {
    final s = context.dependOnInheritedWidgetOfExactType<ShellLayout>();
    return s?.embedded ?? false;
  }

  @override
  bool updateShouldNotify(ShellLayout oldWidget) =>
      embedded != oldWidget.embedded;
}

// ============================================================
// Route panes — /home, /:slug, /:slug/:postId
// ============================================================

/// /home — the circles overview. Rendered inside the shell chrome (the global
/// top bar sits above it on both desktop and mobile).
class _OverviewPane extends StatelessWidget {
  const _OverviewPane();

  @override
  Widget build(BuildContext context) {
    final gc = GroupsScope.of(context);
    // Wait until we know whether the caller has a profile before deciding what
    // to show — otherwise onboarding would flash for existing users.
    if (!gc.profileLoaded) {
      return const Center(child: CircularProgressIndicator());
    }
    // A signed-in user with no `users` row can't create or join circles yet.
    if (!gc.hasProfile) {
      return const _OnboardingPane();
    }
    return _CirclesOverview(
      groups: gc.groups,
      error: gc.error,
      displayName: gc.displayName,
      onOpen: (slug) => context.go('/$slug'),
    );
  }
}

/// /:slug — one circle's feed. Resolves the slug against the shared groups
/// cache (loading it if a deep link landed here first).
class _FeedPane extends StatelessWidget {
  const _FeedPane({required this.slug});

  final String slug;

  @override
  Widget build(BuildContext context) {
    final gc = GroupsScope.of(context);
    final embedded = ShellLayout.embeddedOf(context);
    if (gc.groups == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final g = gc.bySlug(slug);
    if (g == null) {
      return _NotFoundPane(
        embedded: embedded,
        message: "That circle doesn't exist or you're not in it.",
      );
    }
    return FeedScreen(
      key: ValueKey(g['id']),
      groupId: g['id'] as String,
      groupName: g['name'] as String,
      groupSlug: slug,
      embedded: embedded,
    );
  }
}

/// /:slug/:postId — a single post and its tea (comments). The URL carries a
/// short post id (first 8 chars of the UUID); we resolve it against the
/// group's feed to get the full post row + the caller's alias, then hand off
/// to [CommentsScreen].
class _PostPane extends StatefulWidget {
  const _PostPane({super.key, required this.slug, required this.postId});

  final String slug;
  final String postId; // short id from the URL

  @override
  State<_PostPane> createState() => _PostPaneState();
}

class _PostPaneState extends State<_PostPane> {
  Map<String, dynamic>? _post; // null while loading / unresolved
  String? _myAlias;
  Object? _error;
  bool _resolved = false; // finished the lookup (post may still be null)
  String? _loadedForGroupId;

  /// Resolve once the groups cache is ready and we know the group id.
  void _maybeLoad(String groupId) {
    if (_loadedForGroupId == groupId) return;
    _loadedForGroupId = groupId;
    _load(groupId);
  }

  Future<void> _load(String groupId) async {
    try {
      // posts_feed enforces membership; pull the group's posts and match the
      // one whose id starts with the short id from the URL.
      final rows = await supabase
          .from('posts_feed')
          .select('id, author_alias, body')
          .eq('group_id', groupId)
          .order('created_at', ascending: false);
      final list = (rows as List).cast<Map<String, dynamic>>();
      Map<String, dynamic>? match;
      for (final p in list) {
        if ((p['id'] as String).startsWith(widget.postId)) {
          match = p;
          break;
        }
      }
      // Best-effort: the caller's alias in this group, for composing tea.
      // (Same source as the feed — group_members_view, is_me = true.)
      String? alias;
      try {
        final arows = await supabase
            .from('group_members_view')
            .select('alias')
            .eq('group_id', groupId)
            .eq('is_me', true)
            .limit(1);
        if (arows.isNotEmpty) alias = arows.first['alias'] as String?;
      } catch (_) {
        // Non-fatal — the composer just won't be available.
      }
      if (mounted) {
        setState(() {
          _post = match;
          _myAlias = alias;
          _resolved = true;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final gc = GroupsScope.of(context);
    final embedded = ShellLayout.embeddedOf(context);
    if (gc.groups == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final g = gc.bySlug(widget.slug);
    if (g == null) {
      return _NotFoundPane(
          embedded: embedded, message: "That circle doesn't exist.");
    }
    _maybeLoad(g['id'] as String);

    if (_error != null) {
      return _NotFoundPane(
          embedded: embedded, message: 'Could not load this post.');
    }
    if (!_resolved) {
      return const Center(child: CircularProgressIndicator());
    }
    final post = _post;
    if (post == null) {
      return _NotFoundPane(
          embedded: embedded, message: "That post doesn't exist anymore.");
    }
    return CommentsScreen(
      key: ValueKey('post-${post['id']}'),
      postId: post['id'] as String,
      postAlias: (post['author_alias'] as String?) ?? 'anon',
      postBody: post['body'] as String?,
      myAlias: _myAlias,
    );
  }
}

/// Simple "not found" filler for an unresolved slug/post.
class _NotFoundPane extends StatelessWidget {
  const _NotFoundPane({required this.embedded, required this.message});

  final bool embedded;
  final String message;

  @override
  Widget build(BuildContext context) {
    final body = Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 40, color: context.gt.onSurfaceFaint),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(color: context.gt.onSurfaceMuted)),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => context.go('/home'),
              child: const Text('Back to your circles'),
            ),
          ],
        ),
      ),
    );
    if (embedded) return body;
    return Scaffold(
      appBar: AppBar(backgroundColor: context.gt.accent, foregroundColor: context.gt.onAccent),
      body: body,
    );
  }
}

// ============================================================
// /me — your profile
// ============================================================
// Reads fn_my_profile() and shows the account's display name + basics, plus
// entry points for Theme and (destructive) account deletion. Renders
// inside the shell chrome (the global top bar sits above it).
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _profile; // null while loading
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await supabase.rpc('fn_my_profile');
      if (mounted && rows is List && rows.isNotEmpty) {
        setState(() => _profile = (rows.first as Map).cast<String, dynamic>());
      } else if (mounted) {
        setState(() => _profile = {});
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(child: Text('Error: $_error'));
    }
    final p = _profile;
    if (p == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final name = (p['display_name'] as String?) ?? 'you';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '🙂';
    final email = supabase.auth.currentUser?.email ?? '';

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: const EdgeInsets.all(28),
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 34,
                  backgroundColor: context.gt.accent,
                  child: Text(initial,
                      style: TextStyle(
                          color: context.gt.onAccent,
                          fontSize: 28,
                          fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: _headerFont(size: 24)),
                      if (email.isNotEmpty)
                        Text(email,
                            style: TextStyle(color: context.gt.onSurfaceMuted)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Your identity is private. In each circle you post under an '
              'anonymous alias — this name is only for you.',
              style: TextStyle(color: context.gt.onSurfaceMuted, height: 1.3),
            ),
            const SizedBox(height: 24),
            _infoRow(
              icon: Icons.wc_outlined,
              label: 'Gender',
              value: _genderLabel(p['gender'] as String?),
            ),
            if ((p['date_of_birth'] as String?) != null)
              _infoRow(
                icon: Icons.cake_outlined,
                label: 'Date of birth',
                value: (p['date_of_birth'] as String).split('T').first,
              ),
            const SizedBox(height: 12),
            _profileTile(
              icon: Icons.palette_outlined,
              title: 'Theme',
              subtitle:
                  '${themeController.theme.emoji}  ${themeController.theme.name}',
              onTap: () => _showThemeSheet(context),
            ),
            _profileTile(
              icon: Icons.logout,
              title: 'Log Out',
              onTap: () => supabase.auth.signOut(),
            ),
            const Divider(height: 32),
            _profileTile(
              icon: Icons.delete_forever,
              title: 'Delete account',
              color: context.gt.danger,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DeleteAccountScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Friendly label for a stored gender enum. Falls back to a title-cased
  /// version of the raw enum for values not in [_genderOptions], and shows
  /// "Prefer not to say" when it's null.
  static String _genderLabel(String? g) {
    if (g == null) return 'Prefer not to say';
    final known = _genderOptions[g];
    if (known != null) return known;
    return g
        .toLowerCase()
        .split('_')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  /// A read-only "label: value" row for profile facts (gender, DOB).
  Widget _infoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: context.gt.onSurfaceMuted),
          const SizedBox(width: 16),
          Text(label,
              style: TextStyle(color: context.gt.onSurfaceMuted)),
          const Spacer(),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _profileTile({
    required IconData icon,
    required String title,
    String? subtitle,
    Color? color,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: color),
      title: Text(title, style: TextStyle(color: color)),
      subtitle: subtitle == null ? null : Text(subtitle),
      onTap: onTap,
    );
  }
}

// ============================================================
// Onboarding — create the caller's profile row
// ============================================================
// The gender values the DB enum accepts, mapped to friendly labels. We surface
// a short list here (null = "Prefer not to say", stored as NULL); the full enum
// has more variants but this keeps first-run frictionless.
const Map<String?, String> _genderOptions = {
  'WOMAN': 'Woman',
  'MAN': 'Man',
  'NON_BINARY': 'Non-binary',
  null: 'Prefer not to say',
};

/// Shown on /home when the signed-in user has an auth account but no `users`
/// row yet. Collects the minimum the schema requires (display name + DOB, both
/// NOT NULL; gender optional) and inserts the profile, then refreshes so the
/// real landing renders.
class _OnboardingPane extends StatefulWidget {
  const _OnboardingPane();

  @override
  State<_OnboardingPane> createState() => _OnboardingPaneState();
}

class _OnboardingPaneState extends State<_OnboardingPane> {
  final _name = TextEditingController();
  String? _gender; // null = prefer not to say
  DateTime? _dob;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    // Must be at least 13 (DB CHECK). Default the picker near a plausible adult
    // birth year so it's a short scroll either way.
    final maxDob = DateTime(now.year - 13, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 20, now.month, now.day),
      firstDate: DateTime(1920),
      lastDate: maxDob,
      helpText: 'Your date of birth',
    );
    if (picked != null) setState(() => _dob = picked);
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Pick a display name.');
      return;
    }
    if (_dob == null) {
      setState(() => _error = 'Add your date of birth.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final uid = supabase.auth.currentUser!.id;
      final dob = '${_dob!.year.toString().padLeft(4, '0')}-'
          '${_dob!.month.toString().padLeft(2, '0')}-'
          '${_dob!.day.toString().padLeft(2, '0')}';
      await supabase.from('users').insert({
        'id': uid,
        'auth_subject': uid,
        'display_name': name,
        'date_of_birth': dob,
        if (_gender != null) 'gender': _gender,
      });
      await groupsController.refresh();
      // refresh() flips hasProfile → the parent rebuilds into _CirclesOverview.
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(32),
          children: [
            const Text('🌸', style: TextStyle(fontSize: 44)),
            const SizedBox(height: 12),
            Text('Welcome to GirlTea', style: _headerFont(size: 26)),
            const SizedBox(height: 6),
            Text(
              "Let's set up your profile. This is how you'll show up inside "
              'your circles.',
              style: TextStyle(color: context.gt.onSurfaceMuted, fontSize: 15, height: 1.4),
            ),
            const SizedBox(height: 28),
            TextField(
              controller: _name,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Display name',
                hintText: 'e.g. Diya',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String?>(
              initialValue: _gender,
              decoration: const InputDecoration(
                labelText: 'Gender',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final e in _genderOptions.entries)
                  DropdownMenuItem<String?>(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) => setState(() => _gender = v),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _pickDob,
              icon: const Icon(Icons.cake_outlined),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                alignment: Alignment.centerLeft,
              ),
              label: Text(
                _dob == null
                    ? 'Date of birth'
                    : 'Born ${_dob!.year}-${_dob!.month.toString().padLeft(2, '0')}-${_dob!.day.toString().padLeft(2, '0')}',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: TextStyle(color: context.gt.accent)),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: context.gt.accent,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _saving
                  ? SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: context.gt.onAccent),
                    )
                  : const Text('Continue'),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// Create circle — sheet + flow helper
// ============================================================
// group_policy values the backend accepts, with a short "who's this for" hint.
const Map<String, ({String label, String hint})> _policyOptions = {
  'GENDER_NEUTRAL': (label: 'Gender-neutral', hint: 'Anyone can join'),
  'WOMEN_ONLY': (label: 'Women only', hint: 'Only women can join'),
  'MIXED': (label: 'Mixed', hint: 'Open to all genders'),
};

/// The policies a caller with [gender] is allowed to create, mirroring the
/// backend check in `fn_create_group_with_owner`: GENDER_NEUTRAL is always
/// allowed; MIXED needs any gender set; WOMEN_ONLY needs gender = WOMAN. We
/// filter the picker to these so nobody can pick an option that would only
/// come back as a server error.
List<String> _policiesForGender(String? gender) {
  return [
    'GENDER_NEUTRAL',
    if (gender != null) 'MIXED',
    if (gender == 'WOMAN') 'WOMEN_ONLY',
  ];
}

/// Opens the create-circle sheet, then (on success) refreshes the groups cache
/// and navigates into the brand-new circle's feed. Guards on having a profile —
/// the backend RPC would reject a callerless request anyway, but this gives a
/// friendlier path. Safe to call from the rail, the overview, or the empty state.
Future<void> startCreateCircle(BuildContext context) async {
  if (!groupsController.hasProfile) return;
  final newId = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.gt.surfaceRaised,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _CreateCircleSheet(),
  );
  if (newId == null) return;
  await groupsController.refresh();
  final created = groupsController.groups?.firstWhere(
    (g) => g['id'] == newId,
    orElse: () => <String, dynamic>{},
  );
  final slug = created?['slug'] as String?;
  if (slug != null && context.mounted) context.go('/$slug');
}

class _CreateCircleSheet extends StatefulWidget {
  const _CreateCircleSheet();

  @override
  State<_CreateCircleSheet> createState() => _CreateCircleSheetState();
}

class _CreateCircleSheetState extends State<_CreateCircleSheet> {
  final _name = TextEditingController();
  final _desc = TextEditingController();
  String _policy = 'GENDER_NEUTRAL';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give your circle a name.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final id = await supabase.rpc('fn_create_group_with_owner', params: {
        'p_name': name,
        'p_description': _desc.text.trim().isEmpty ? null : _desc.text.trim(),
        'p_policy': _policy,
        'p_visibility': 'LINK_ONLY',
        'p_category_tags': <String>[],
      });
      if (mounted) Navigator.of(context).pop(id as String);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 20,
        bottom: 24 + bottomInset,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: context.gt.hairline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('Create a circle', style: _headerFont(size: 22)),
            const SizedBox(height: 4),
            Text(
              'A private space for your people. Invite them with a link once '
              "it's made.",
              style: TextStyle(color: context.gt.onSurfaceMuted, height: 1.4),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _name,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Circle name',
                hintText: 'e.g. The Group Chat',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _desc,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                hintText: "What's this circle about?",
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 18),
            const Text('Who can join',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            for (final key in _policiesForGender(groupsController.gender))
              RadioListTile<String>(
                value: key,
                groupValue: _policy,
                onChanged: (v) => setState(() => _policy = v!),
                activeColor: context.gt.accent,
                contentPadding: EdgeInsets.zero,
                title: Text(_policyOptions[key]!.label),
                subtitle: Text(_policyOptions[key]!.hint),
              ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: context.gt.accent)),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _create,
                style: FilledButton.styleFrom(
                  backgroundColor: context.gt.accent,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _saving
                    ? SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: context.gt.onAccent),
                      )
                    : const Text('Create circle'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// Desktop shell — circles overview (center pane before a pick)
// ============================================================
// The landing view after login: a warm welcome + a responsive grid of the
// circles you're in. Clicking one opens its feed in the same pane.
class _CirclesOverview extends StatelessWidget {
  const _CirclesOverview({
    required this.groups,
    required this.error,
    required this.displayName,
    required this.onOpen,
  });

  final List<Map<String, dynamic>>? groups;
  final Object? error;
  final String? displayName;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return Center(child: Text('Error: $error'));
    }
    final list = groups;
    if (list == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (list.isEmpty) {
      return _EmptyCirclesState(displayName: displayName);
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          padding: const EdgeInsets.all(32),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName == null
                            ? 'Your circles'
                            : 'Hi, $displayName 👋',
                        style: _headerFont(size: 26),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'The people who know you. Pick a circle to catch up '
                        'on the tea.',
                        style: TextStyle(color: context.gt.onSurfaceMuted, fontSize: 15),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                FilledButton.icon(
                  onPressed: () => startCreateCircle(context),
                  icon: const Icon(Icons.add),
                  label: const Text('New Circle'),
                  style: FilledButton.styleFrom(
                    backgroundColor: context.gt.accent,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 14),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            LayoutBuilder(
              builder: (context, c) {
                // 2 columns when there's room, otherwise 1.
                final cols = c.maxWidth >= 520 ? 2 : 1;
                final cardWidth =
                    cols == 2 ? (c.maxWidth - 16) / 2 : c.maxWidth;
                return Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    for (final g in list)
                      SizedBox(
                        width: cardWidth,
                        child: _CircleOverviewCard(
                          group: g,
                          onOpen: () => onOpen(g['slug'] as String),
                        ),
                      ),
                    SizedBox(
                      width: cardWidth,
                      child: _CreateCircleCard(
                        onTap: () => startCreateCircle(context),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 36),
            Text('Recent Spills', style: _headerFont(size: 20)),
            const SizedBox(height: 12),
            _RecentSpills(groups: list, onOpen: onOpen),
          ],
        ),
      ),
    );
  }
}

/// A cross-circle feed of the latest posts, with filter chips (All Circles +
/// one per circle). Reads the `posts_feed` view, which already scopes rows to
/// the caller's groups, so a single query covers every circle at once. Tapping
/// a spill opens that post in its circle.
class _RecentSpills extends StatefulWidget {
  const _RecentSpills({required this.groups, required this.onOpen});

  final List<Map<String, dynamic>> groups;
  final ValueChanged<String> onOpen; // receives a circle slug

  @override
  State<_RecentSpills> createState() => _RecentSpillsState();
}

class _RecentSpillsState extends State<_RecentSpills> {
  late Future<List<Map<String, dynamic>>> _future;
  String? _filterGroupId; // null = All Circles

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final rows = await supabase
        .from('posts_feed')
        .select(
            'id, group_id, author_alias, type, body, thumbnail_url, upvote_count, created_at')
        .order('created_at', ascending: false)
        .limit(30);
    return (rows as List).cast<Map<String, dynamic>>();
  }

  String _groupName(String id) {
    for (final g in widget.groups) {
      if (g['id'] == id) return (g['name'] as String?) ?? 'Circle';
    }
    return 'Circle';
  }

  String? _groupSlug(String id) {
    for (final g in widget.groups) {
      if (g['id'] == id) return g['slug'] as String?;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final all = snap.data ?? const [];
        final posts = _filterGroupId == null
            ? all
            : all.where((p) => p['group_id'] == _filterGroupId).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Filter chips.
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _chip('All Circles', _filterGroupId == null,
                    () => setState(() => _filterGroupId = null)),
                for (final g in widget.groups)
                  _chip(
                    (g['name'] as String?) ?? 'Circle',
                    _filterGroupId == g['id'],
                    () => setState(() => _filterGroupId = g['id'] as String),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (posts.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('No spills yet. Be the first to share something.',
                    style: TextStyle(color: context.gt.onSurfaceMuted)),
              )
            else
              for (final p in posts)
                _SpillTile(
                  post: p,
                  circleName: _groupName(p['group_id'] as String),
                  onTap: () {
                    final slug = _groupSlug(p['group_id'] as String);
                    if (slug != null) widget.onOpen(slug);
                  },
                ),
          ],
        );
      },
    );
  }

  Widget _chip(String label, bool active, VoidCallback onTap) {
    return ChoiceChip(
      label: Text(label),
      selected: active,
      onSelected: (_) => onTap(),
      showCheckmark: false,
      selectedColor: context.gt.accent,
      backgroundColor: context.gt.surfaceRaised,
      labelStyle: TextStyle(
        color: active ? context.gt.onAccent : context.gt.onSurface,
        fontWeight: active ? FontWeight.w600 : FontWeight.w500,
      ),
      shape: StadiumBorder(
        side: BorderSide(color: active ? context.gt.accent : context.gt.hairline),
      ),
    );
  }
}

/// One row in the Recent Spills feed: circle name + alias + time, a snippet or
/// media hint, and the upvote count.
class _SpillTile extends StatelessWidget {
  const _SpillTile({
    required this.post,
    required this.circleName,
    required this.onTap,
  });

  final Map<String, dynamic> post;
  final String circleName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final type = (post['type'] as String?) ?? 'TEXT';
    final body = (post['body'] as String?)?.trim();
    final snippet = switch (type) {
      'VIDEO' => '📹 Video',
      'VOICE' => '🎧 Voice note',
      'IMAGE' => '📷 Photo',
      _ => (body == null || body.isEmpty) ? 'A spill' : body,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: context.gt.surfaceRaised,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: context.gt.hairline),
            ),
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(circleName,
                              style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: context.gt.brand,
                                  fontSize: 13)),
                          const SizedBox(width: 8),
                          Text(
                            '${post['author_alias'] ?? ''} · ${_timeAgo(post['created_at'] as String?)}',
                            style: TextStyle(
                                color: context.gt.onSurfaceMuted, fontSize: 12),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        snippet,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(height: 1.3),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  children: [
                    Icon(Icons.favorite, size: 16, color: context.gt.accent),
                    const SizedBox(height: 2),
                    Text('${post['upvote_count'] ?? 0}',
                        style: TextStyle(
                            fontSize: 12, color: context.gt.onSurfaceMuted)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The warm empty state shown when you're in no circles yet — a big invitation
/// to make your first one, matching the brand's cream/pink feel.
class _EmptyCirclesState extends StatelessWidget {
  const _EmptyCirclesState({required this.displayName});

  final String? displayName;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🌸', style: TextStyle(fontSize: 56)),
              const SizedBox(height: 16),
              Text(
                displayName == null
                    ? 'Your first circle awaits'
                    : 'Your first circle awaits, $displayName',
                textAlign: TextAlign.center,
                style: _headerFont(size: 24),
              ),
              const SizedBox(height: 8),
              Text(
                "Circles are private little worlds for your people. Spill the "
                'tea, share memories, and keep it just between you.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: context.gt.onSurfaceMuted, fontSize: 15, height: 1.5),
              ),
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: () => startCreateCircle(context),
                icon: const Icon(Icons.add),
                label: const Text('Create your first circle'),
                style: FilledButton.styleFrom(
                  backgroundColor: context.gt.accent,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A dashed, pink-bordered call-to-action card that sits alongside the real
/// circle cards so "make another one" is always one tap away.
class _CreateCircleCard extends StatelessWidget {
  const _CreateCircleCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.gt.accentSoft,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.gt.accent.withValues(alpha: 0.4)),
          ),
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: context.gt.accent.withValues(alpha: 0.15),
                child: Icon(Icons.add, color: context.gt.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Create New Circle',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: context.gt.accent),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CircleOverviewCard extends StatelessWidget {
  const _CircleOverviewCard({required this.group, required this.onOpen});

  final Map<String, dynamic> group;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final glyph = _circleGlyph(group['id'] as String);
    final desc = (group['description'] ?? '') as String;
    return Material(
      color: context.gt.surfaceRaised,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onOpen,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.gt.hairline),
          ),
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: glyph.color,
                    child: Text(glyph.emoji,
                        style: const TextStyle(fontSize: 20)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          group['name'] ?? '',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        Text('${group['member_count']} members',
                            style: TextStyle(
                                color: context.gt.onSurfaceMuted, fontSize: 13)),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: context.gt.onSurfaceFaint),
                ],
              ),
              if (desc.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  desc,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: context.gt.onSurfaceMuted, height: 1.3),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// Desktop shell — left rail of circles
// ============================================================
class _CircleRail extends StatelessWidget {
  const _CircleRail({
    required this.groups,
    required this.error,
    required this.selectedSlug,
    required this.displayName,
    required this.onSelect,
  });

  final List<Map<String, dynamic>>? groups;
  final Object? error;
  final String? selectedSlug;
  final String? displayName;
  final ValueChanged<String> onSelect; // receives a group slug

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 264,
      color: context.gt.surfaceRaised,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: FilledButton.icon(
              onPressed: () => startCreateCircle(context),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('New Circle'),
              style: FilledButton.styleFrom(
                backgroundColor: context.gt.accent,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Text('YOUR CIRCLES',
                style: TextStyle(
                    color: context.gt.onSurfaceFaint,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8)),
          ),
          Expanded(
            child: Builder(
              builder: (context) {
                if (error != null) {
                  return Center(child: Text('Error: $error'));
                }
                final list = groups;
                if (list == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (list.isEmpty) {
                  return Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('You are not in any circles yet.',
                        style: TextStyle(color: context.gt.onSurfaceMuted)),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final g = list[i];
                    final id = g['id'] as String;
                    final slug = g['slug'] as String;
                    final glyph = _circleGlyph(id);
                    final active = slug == selectedSlug;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Material(
                        color: active ? context.gt.accentSoft : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => onSelect(slug),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 10),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 16,
                                  backgroundColor: glyph.color,
                                  child: Text(glyph.emoji,
                                      style: const TextStyle(fontSize: 15)),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        g['name'] ?? '',
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontWeight: active
                                              ? FontWeight.bold
                                              : FontWeight.w500,
                                          color: active
                                              ? context.gt.accent
                                              : context.gt.onSurface,
                                        ),
                                      ),
                                      Text('${g['member_count']}',
                                          style: TextStyle(
                                              color: context.gt.onSurfaceFaint,
                                              fontSize: 12)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          // "Safe space" reassurance card — the warm note from the mockup.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.gt.lavender.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Text('🌷', style: TextStyle(fontSize: 22)),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'A safe space for the conversations that matter.',
                      style: TextStyle(
                          color: context.gt.onSurface, fontSize: 12.5, height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (displayName != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Row(
                children: [
                  Icon(Icons.person_outline,
                      size: 18, color: context.gt.onSurfaceFaint),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(displayName!,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: context.gt.onSurfaceMuted)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ============================================================
// Desktop shell — right circle panel (about + members + memories)
// ============================================================
class _CirclePanel extends StatefulWidget {
  const _CirclePanel({super.key, required this.group});

  final Map<String, dynamic> group;

  @override
  State<_CirclePanel> createState() => _CirclePanelState();
}

class _CirclePanelState extends State<_CirclePanel> {
  List<Map<String, dynamic>>? _members; // null = loading

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    try {
      final rows = await supabase
          .from('group_members_view')
          .select('alias, is_me')
          .eq('group_id', widget.group['id'] as String);
      if (mounted) {
        setState(() => _members = (rows as List).cast<Map<String, dynamic>>());
      }
    } catch (_) {
      if (mounted) setState(() => _members = const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.group;
    final glyph = _circleGlyph(g['id'] as String);
    final desc = (g['description'] ?? '') as String;
    final members = _members;
    return Container(
      width: 300,
      color: context.gt.surfaceRaised,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: CircleAvatar(
              radius: 28,
              backgroundColor: glyph.color,
              child: Text(glyph.emoji, style: const TextStyle(fontSize: 26)),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(g['name'] ?? '',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text('${g['member_count']} members',
                style: TextStyle(color: context.gt.onSurfaceMuted, fontSize: 13)),
          ),
          if (desc.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(desc,
                style: TextStyle(color: context.gt.onSurface, height: 1.4)),
          ],
          const SizedBox(height: 24),
          Text('IN THIS CIRCLE',
              style: TextStyle(
                  color: context.gt.onSurfaceFaint,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8)),
          const SizedBox(height: 8),
          if (members == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            )
          else
            for (final m in members)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: context.gt.accentSoft,
                      child: Text('🌷', style: TextStyle(fontSize: 12)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(m['alias'] ?? 'anon',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: context.gt.onSurface)),
                    ),
                    if (m['is_me'] == true)
                      Text('you',
                          style: TextStyle(
                              color: context.gt.accent,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.gt.accentSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.bookmark_border, size: 18, color: context.gt.accent),
                    SizedBox(width: 6),
                    Text('Circle Memories',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, color: context.gt.accent)),
                  ],
                ),
                SizedBox(height: 6),
                Text('Tea you save before it goes cold will live here.',
                    style: TextStyle(color: context.gt.onSurfaceMuted, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// Feed — posts in a group (read through posts_feed view)
// ============================================================
class FeedScreen extends StatefulWidget {
  const FeedScreen({
    super.key,
    required this.groupId,
    required this.groupName,
    this.groupSlug,
    this.embedded = false,
  });

  final String groupId;
  final String groupName;

  /// The circle's URL slug, used to route to a post at /:slug/:postId.
  /// Null only in legacy call sites that push the feed directly.
  final String? groupSlug;

  /// When true, the feed renders as a pane inside the desktop shell (its own
  /// slim header + compose button, no Scaffold/back button). When false it is
  /// a full pushed screen with an AppBar + FAB (mobile navigation).
  final bool embedded;

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  List<Map<String, dynamic>>? _posts; // null = still loading
  Object? _error;
  String? _myAlias; // this user's anonymized alias in this group
  bool _isModerator = false; // OWNER/ADMIN of this group
  int _pendingCount = 0; // join requests in this circle awaiting my vote
  final Set<String> _myUpvotes = {}; // post ids I've upvoted

  @override
  void initState() {
    super.initState();
    _loadPosts();
    _loadMyAlias();
    _loadMyUpvotes();
    _loadModeratorStatus();
    _loadPendingCount();
    // Reload when a post is spilled from the global top-bar button.
    feedRefresh.addListener(_onFeedRefresh);
  }

  @override
  void dispose() {
    feedRefresh.removeListener(_onFeedRefresh);
    super.dispose();
  }

  void _onFeedRefresh() => _loadPosts();

  Future<void> _loadModeratorStatus() async {
    // Gates the moderation-queue entry point in the app bar.
    try {
      final isMod = await supabase
          .rpc('fn_is_group_moderator', params: {'p_group_id': widget.groupId});
      if (mounted && isMod is bool) setState(() => _isModerator = isMod);
    } catch (_) {
      // Non-fatal: just don't show the moderator affordance.
    }
  }

  Future<void> _loadPendingCount() async {
    // How many join requests in THIS circle are waiting on my vote — powers
    // the badge on the "Requests" action. The RPC returns pending requests
    // across all my circles, so filter to this group.
    try {
      final rows = await supabase.rpc('fn_pending_join_requests_for_me');
      if (rows is List && mounted) {
        final n = rows
            .where((r) => r['group_id'] == widget.groupId)
            .length;
        setState(() => _pendingCount = n);
      }
    } catch (_) {
      // Non-fatal: just don't badge the action.
    }
  }

  Future<void> _openInvite() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => InviteSheet(
        groupId: widget.groupId,
        groupName: widget.groupName,
      ),
    );
  }

  Future<void> _openRequests() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => JoinRequestsScreen(
          groupId: widget.groupId,
          groupName: widget.groupName,
        ),
      ),
    );
    // Votes may have resolved requests — refresh the badge on return.
    _loadPendingCount();
  }

  // Invite + Requests actions, available to ANY member. [color] is null in the
  // AppBar (inherits onAccent) and the circle accent in the desktop pane.
  List<Widget> _memberActions(Color? color) {
    return [
      IconButton(
        tooltip: 'Invite to this circle',
        icon: Icon(Icons.person_add_alt_1_outlined, color: color),
        onPressed: _openInvite,
      ),
      IconButton(
        tooltip: 'Join requests',
        icon: Badge.count(
          count: _pendingCount,
          isLabelVisible: _pendingCount > 0,
          child: Icon(Icons.how_to_reg_outlined, color: color),
        ),
        onPressed: _openRequests,
      ),
    ];
  }

  Future<void> _loadPosts() async {
    // Direct SELECT on `posts` is revoked by RLS — read the view,
    // which enforces membership and exposes only the alias.
    try {
      final rows = await supabase
          .from('posts_feed')
          .select(
              'id, author_alias, type, body, media_url, duration_seconds, upvote_count, created_at, is_mine')
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

  Future<void> _deletePost(Map<String, dynamic> post) async {
    final postId = post['id'] as String?;
    if (postId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this post?'),
        content: const Text(
            'It will be removed from the feed. This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: context.gt.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    // Soft-delete via UPDATE (RLS allows the author; there is no DELETE
    // policy on posts). The feed view filters is_deleted = TRUE, so it
    // drops out on the next load. Remove it locally right away.
    final removed = _posts;
    setState(() => _posts =
        _posts?.where((p) => p['id'] != postId).toList() ?? _posts);
    try {
      await supabase
          .from('posts')
          .update({'is_deleted': true, 'deleted_at': DateTime.now().toIso8601String()})
          .eq('id', postId);
    } on PostgrestException catch (e) {
      if (mounted) {
        setState(() => _posts = removed); // roll back
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete: ${e.message}')),
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
    final postId = post['id'] as String?;
    final slug = widget.groupSlug;
    // Preferred path: give the post a real, shareable URL (/:slug/:shortId).
    if (postId != null && slug != null) {
      context.go('/$slug/${_postShortId(postId)}');
      return;
    }
    // Fallback for legacy call sites that push the feed without a slug.
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CommentsScreen(
          postId: postId ?? '',
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

  // The scrolling list of posts, shared by both the embedded pane and the
  // full mobile screen.
  Widget _buildFeedBody() {
    if (_error != null) {
      return Center(child: Text('Error: $_error'));
    }
    final posts = _posts;
    if (posts == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (posts.isEmpty) {
      return LayoutBuilder(
        builder: (context, constraints) => RefreshIndicator(
          onRefresh: _loadPosts,
          child: ListView(
            children: [
              SizedBox(
                height: constraints.maxHeight,
                child: const Center(
                  child: Text('No tea yet. Be the first to spill ☕'),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadPosts,
      // Center the column of cards and cap its width so the feed stays
      // readable on a wide desktop pane (Reddit does the same).
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            itemCount: posts.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) => _postCard(posts[i]),
          ),
        ),
      ),
    );
  }

  // A single post card: header (alias · time ago) → body/media → one quiet
  // action row. Deliberately roomy and low-density.
  Widget _postCard(Map<String, dynamic> p) {
    final postId = p['id'] as String?;
    final upvoted = postId != null && _myUpvotes.contains(postId);
    final ago = _timeAgo(p['created_at'] as String?);
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: context.gt.hairline),
      ),
      child: InkWell(
        onTap: postId == null ? null : () => _openComments(p),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            p['author_alias'] ?? 'anon',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontWeight: FontWeight.bold, color: context.gt.accent),
                          ),
                        ),
                        if (ago.isNotEmpty) ...[
                          Text('  ·  ',
                              style: TextStyle(color: context.gt.onSurfaceFaint)),
                          Text(ago,
                              style: TextStyle(
                                  color: context.gt.onSurfaceMuted, fontSize: 13)),
                        ],
                      ],
                    ),
                  ),
                  if (postId != null)
                    _PostMenu(
                      isMine: p['is_mine'] == true,
                      onDelete: () => _deletePost(p),
                      onReport: () => showReportSheet(
                        context,
                        targetType: 'POST',
                        targetId: postId,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
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
                  const SizedBox(height: 10),
              ],
              if ((p['body'] as String?)?.isNotEmpty ?? false)
                Text(p['body'] as String,
                    style: const TextStyle(fontSize: 15, height: 1.4))
              else if (p['type'] == 'TEXT')
                Text('[${p['type']}]'),
              const SizedBox(height: 12),
              Row(
                children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    iconSize: 20,
                    color: context.gt.accent,
                    tooltip: upvoted ? 'Remove tea drop' : 'Tea drop',
                    icon: Icon(
                        upvoted ? Icons.favorite : Icons.favorite_border),
                    onPressed: postId == null ? null : () => _toggleUpvote(p),
                  ),
                  const SizedBox(width: 6),
                  Text('${p['upvote_count']}',
                      style: TextStyle(color: context.gt.onSurfaceMuted)),
                  const SizedBox(width: 20),
                  Icon(Icons.mode_comment_outlined,
                      size: 18, color: context.gt.onSurfaceMuted),
                  const SizedBox(width: 6),
                  Text('Spill', style: TextStyle(color: context.gt.onSurfaceMuted)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Embedded: a pane inside the desktop shell — slim header row + the feed,
    // no Scaffold/back button (the shell owns those).
    if (widget.embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: context.gt.hairline)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.groupName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                ..._memberActions(context.gt.accent),
                if (_isModerator)
                  IconButton(
                    tooltip: 'Moderation queue',
                    icon: Icon(Icons.shield_outlined, color: context.gt.accent),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            ModerationQueueScreen(groupName: widget.groupName),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(child: _buildFeedBody()),
        ],
      );
    }

    // Full screen: mobile navigation (pushed route with AppBar + FAB).
    return Scaffold(
      appBar: AppBar(
        backgroundColor: context.gt.accent,
        foregroundColor: context.gt.onAccent,
        title: Text(widget.groupName),
        actions: [
          ..._memberActions(null),
          if (_isModerator)
            IconButton(
              tooltip: 'Moderation queue',
              icon: const Icon(Icons.shield_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      ModerationQueueScreen(groupName: widget.groupName),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: context.gt.accent,
        foregroundColor: context.gt.onAccent,
        onPressed: _myAlias == null ? null : _openComposer,
        icon: const Icon(Icons.edit),
        label: const Text('Spill'),
      ),
      body: _buildFeedBody(),
    );
  }
}

// A post's overflow menu: the author sees "Delete", everyone else
// sees "Report".
class _PostMenu extends StatelessWidget {
  const _PostMenu({
    required this.isMine,
    required this.onDelete,
    required this.onReport,
  });

  final bool isMine;
  final VoidCallback onDelete;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_horiz, size: 20, color: context.gt.onSurfaceFaint),
      tooltip: 'More',
      onSelected: (v) => v == 'delete' ? onDelete() : onReport(),
      itemBuilder: (_) => [
        if (isMine)
          PopupMenuItem(
            value: 'delete',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.delete_outline, color: context.gt.danger),
              title: Text('Delete'),
            ),
          )
        else
          const PopupMenuItem(
            value: 'report',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.flag_outlined),
              title: Text('Report'),
            ),
          ),
      ],
    );
  }
}

// ============================================================
// Invites — mint a link, land on it, and vote in new members
// ============================================================
// Any active member can mint a shareable link (fn_create_invite). Opening the
// link (/join/:token) resolves safe metadata and, on "Join", files a request
// that admits the person only after 2 members approve (fn_cast_join_vote).

/// Bottom sheet that mints an invite link and lets a member copy/share it.
class InviteSheet extends StatefulWidget {
  const InviteSheet({super.key, required this.groupId, required this.groupName});

  final String groupId;
  final String groupName;

  @override
  State<InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends State<InviteSheet> {
  String? _link; // null until minted
  Object? _error;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _mint();
  }

  Future<void> _mint() async {
    try {
      final token = await supabase.rpc('fn_create_invite', params: {
        'p_group_id': widget.groupId,
      });
      final origin = html.window.location.origin;
      if (mounted) setState(() => _link = '$origin/join/$token');
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _copy() async {
    final link = _link;
    if (link == null) return;
    try {
      await html.window.navigator.clipboard?.writeText(link);
      if (mounted) setState(() => _copied = true);
    } catch (_) {
      // Clipboard can be blocked; the link is still selectable above.
    }
  }

  @override
  Widget build(BuildContext context) {
    final gt = context.gt;
    return Container(
      decoration: BoxDecoration(
        color: gt.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          24, 20, 24, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: gt.hairline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text('Invite to ${widget.groupName}', style: _headerFont(size: 22)),
          const SizedBox(height: 6),
          Text(
            'Share this link with your girls. Whoever opens it asks to join — '
            'and gets in once 2 members of this circle approve. ☕',
            style: TextStyle(
                color: gt.onSurfaceMuted, fontSize: 14, height: 1.4),
          ),
          const SizedBox(height: 20),
          if (_error != null)
            Text('Could not create a link: $_error',
                style: TextStyle(color: gt.danger))
          else if (_link == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: gt.surfaceSunken,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: gt.hairline),
              ),
              child: SelectableText(
                _link!,
                maxLines: 1,
                style: TextStyle(color: gt.onSurface, fontSize: 13),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: gt.accent,
                  foregroundColor: gt.onAccent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _copy,
                icon: Icon(_copied ? Icons.check : Icons.copy, size: 18),
                label: Text(_copied ? 'Link copied' : 'Copy link'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// /join/:token — the landing a friend sees when they open an invite link.
/// Requires an account with a profile; the router preserves the token through
/// login, and this gates on onboarding before resolving.
class InviteLandingScreen extends StatelessWidget {
  const InviteLandingScreen({super.key, required this.token});

  final String token;

  @override
  Widget build(BuildContext context) {
    final gc = GroupsScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const GirlTeaWordmark(fontSize: 20),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Not now',
          onPressed: () => context.go('/home'),
        ),
      ),
      body: Builder(builder: (context) {
        if (!gc.profileLoaded) {
          return const Center(child: CircularProgressIndicator());
        }
        // Brand-new account: they must finish their profile before joining.
        // Onboarding flips hasProfile and this rebuilds into the invite card.
        if (!gc.hasProfile) return const _OnboardingPane();
        return _InviteResolver(token: token);
      }),
    );
  }
}

class _InviteResolver extends StatefulWidget {
  const _InviteResolver({required this.token});

  final String token;

  @override
  State<_InviteResolver> createState() => _InviteResolverState();
}

class _InviteResolverState extends State<_InviteResolver> {
  Map<String, dynamic>? _invite; // resolved metadata
  Object? _error;
  bool _joining = false;
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    try {
      final rows = await supabase
          .rpc('fn_resolve_invite', params: {'p_token': widget.token});
      if (mounted) {
        setState(() {
          _invite = (rows as List).isEmpty
              ? null
              : (rows.first as Map).cast<String, dynamic>();
          if (_invite == null) _error = 'This circle is no longer available.';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _join() async {
    final inv = _invite;
    if (inv == null) return;
    setState(() => _joining = true);
    try {
      await supabase.rpc('fn_submit_join_request', params: {
        'p_group_id': inv['group_id'],
        'p_token': widget.token,
      });
      // Consumed — don't let the router bounce back here later.
      html.window.localStorage.remove(_pendingInviteKey);
      if (mounted) setState(() => _submitted = true);
    } catch (e) {
      if (mounted) {
        setState(() => _joining = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not send your request: $e')),
        );
      }
    }
  }

  void _openCircle(String groupId) {
    html.window.localStorage.remove(_pendingInviteKey);
    // We only have the group id here; jump into it by slug if we know it.
    for (final g in groupsController.groups ?? const []) {
      if (g['id'] == groupId) {
        context.go('/${g['slug']}');
        return;
      }
    }
    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final gt = context.gt;
    if (_error != null) {
      return _InviteMessage(
        emoji: '🚪',
        title: 'This link didn\'t work',
        body: '$_error',
        actionLabel: 'Go to your circles',
        onAction: () => context.go('/home'),
      );
    }
    final inv = _invite;
    if (inv == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final name = inv['name'] as String? ?? 'A circle';
    final inviter = inv['inviter_name'] as String?;
    final memberCount = inv['member_count'] as int? ?? 0;
    final description = inv['description'] as String?;

    if (inv['already_member'] == true) {
      return _InviteMessage(
        emoji: '💕',
        title: 'You\'re already in $name',
        body: 'Your seat is warm. Head in and see what\'s brewing.',
        actionLabel: 'Open circle',
        onAction: () => _openCircle(inv['group_id'] as String),
      );
    }

    if (_submitted || inv['has_pending_request'] == true) {
      return _InviteMessage(
        emoji: '⏳',
        title: 'Waiting on your girls',
        body:
            'Your request to join $name is in. You\'re in as soon as 2 members '
            'say yes.',
        actionLabel: 'Go to your circles',
        onAction: () => context.go('/home'),
      );
    }

    // The invite card.
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('☕', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 16),
              Text(
                inviter != null && inviter.isNotEmpty
                    ? '$inviter saved you a seat'
                    : 'You\'re invited',
                textAlign: TextAlign.center,
                style: _headerFont(size: 26),
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: gt.surfaceRaised,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: gt.hairline),
                ),
                child: Column(
                  children: [
                    Text(name,
                        textAlign: TextAlign.center,
                        style: _headerFont(size: 22)),
                    const SizedBox(height: 8),
                    if (description != null && description.isNotEmpty) ...[
                      Text(description,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: gt.onSurfaceMuted, height: 1.4)),
                      const SizedBox(height: 12),
                    ],
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.lock_outline,
                            size: 15, color: gt.onSurfaceFaint),
                        const SizedBox(width: 6),
                        Text(
                          '$memberCount ${memberCount == 1 ? 'girl' : 'girls'} · private circle',
                          style: TextStyle(
                              color: gt.onSurfaceFaint, fontSize: 13),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '2 members will need to approve before you\'re in.',
                textAlign: TextAlign.center,
                style: TextStyle(color: gt.onSurfaceFaint, fontSize: 13),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: gt.accent,
                    foregroundColor: gt.onAccent,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: _joining ? null : _join,
                  child: _joining
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Join your girls'),
                ),
              ),
              TextButton(
                onPressed: () => context.go('/home'),
                child: const Text('Not now'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A simple centered emoji + title + body + one action, for invite end-states.
class _InviteMessage extends StatelessWidget {
  const _InviteMessage({
    required this.emoji,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
  });

  final String emoji;
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final gt = context.gt;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 44)),
              const SizedBox(height: 14),
              Text(title, textAlign: TextAlign.center, style: _headerFont(size: 24)),
              const SizedBox(height: 8),
              Text(body,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: gt.onSurfaceMuted, height: 1.4)),
              const SizedBox(height: 22),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: gt.accent,
                  foregroundColor: gt.onAccent,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                ),
                onPressed: onAction,
                child: Text(actionLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The member-facing list of people asking to join this circle, with the
/// Approve / Reject votes that drive the 2-approval quorum (fn_cast_join_vote).
class JoinRequestsScreen extends StatefulWidget {
  const JoinRequestsScreen(
      {super.key, required this.groupId, required this.groupName});

  final String groupId;
  final String groupName;

  @override
  State<JoinRequestsScreen> createState() => _JoinRequestsScreenState();
}

class _JoinRequestsScreenState extends State<JoinRequestsScreen> {
  List<Map<String, dynamic>>? _requests; // null = loading
  Object? _error;
  final Set<String> _voting = {}; // request ids with a vote in flight

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await supabase.rpc('fn_pending_join_requests_for_me');
      if (mounted) {
        setState(() {
          _requests = (rows as List)
              .cast<Map<String, dynamic>>()
              .where((r) => r['group_id'] == widget.groupId)
              .toList();
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _vote(Map<String, dynamic> req, bool approve) async {
    final id = req['id'] as String;
    setState(() => _voting.add(id));
    try {
      await supabase.rpc('fn_cast_join_vote', params: {
        'p_join_request_id': id,
        'p_vote': approve ? 'APPROVE' : 'REJECT',
      });
      // Drop it from the list — it's resolved for me either way.
      if (mounted) {
        setState(() {
          _requests = _requests?.where((r) => r['id'] != id).toList();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(approve ? 'You said yes ☕' : 'Request declined')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not record your vote: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _voting.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final gt = context.gt;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: gt.accent,
        foregroundColor: gt.onAccent,
        title: const Text('Join requests'),
      ),
      body: Builder(builder: (context) {
        if (_error != null) {
          return Center(child: Text('Error: $_error'));
        }
        final reqs = _requests;
        if (reqs == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (reqs.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'No one\'s knocking right now.\nInvite your girls to ${widget.groupName}. ☕',
                textAlign: TextAlign.center,
                style: TextStyle(color: gt.onSurfaceMuted, height: 1.5),
              ),
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: _load,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: reqs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, i) => _requestCard(reqs[i]),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _requestCard(Map<String, dynamic> req) {
    final gt = context.gt;
    final id = req['id'] as String;
    final approvals = (req['approval_count'] as num?)?.toInt() ?? 0;
    final quorum = (req['quorum'] as num?)?.toInt() ?? 2;
    final iHaveVoted = req['i_have_voted'] == true;
    final iCanVote = req['i_can_vote'] == true;
    final busy = _voting.contains(id);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: gt.surfaceRaised,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: gt.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.person_outline, color: gt.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Someone wants to join',
                  style: TextStyle(
                      fontWeight: FontWeight.w600, color: gt.onSurface),
                ),
              ),
              Text('$approvals of $quorum',
                  style: TextStyle(color: gt.onSurfaceMuted, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 12),
          if (iHaveVoted)
            Text('You\'ve voted — waiting on the others.',
                style: TextStyle(color: gt.onSurfaceFaint, fontSize: 13))
          else if (!iCanVote)
            Text('You can\'t vote on this one.',
                style: TextStyle(color: gt.onSurfaceFaint, fontSize: 13))
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: busy ? null : () => _vote(req, false),
                    child: const Text('Decline'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: gt.accent,
                      foregroundColor: gt.onAccent,
                    ),
                    onPressed: busy ? null : () => _vote(req, true),
                    child: busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child:
                                CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Approve'),
                  ),
                ),
              ],
            ),
        ],
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
                color: context.gt.hairline,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.movie_outlined, color: context.gt.accent),
                    const SizedBox(width: 8),
                    Text('Video ready'
                        '${_durationSeconds != null ? ' · ${_fmtDuration(_durationSeconds!)}' : ''}',
                        style: TextStyle(color: context.gt.onSurfaceMuted)),
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
            color: context.gt.accentSoft,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              if (_recording) ...[
                Icon(Icons.fiber_manual_record,
                    color: context.gt.danger, size: 16),
                const SizedBox(width: 8),
                Text('Recording… ${_fmtDuration(_recordSeconds)}',
                    style: TextStyle(color: context.gt.onSurface)),
                const Spacer(),
                TextButton.icon(
                  onPressed: _stopRecording,
                  icon: Icon(Icons.stop_circle, color: context.gt.accent),
                  label: const Text('Stop'),
                ),
              ] else ...[
                Icon(Icons.graphic_eq, color: context.gt.accent),
                const SizedBox(width: 8),
                Text('Voice note'
                    '${_durationSeconds != null ? ' · ${_fmtDuration(_durationSeconds!)}' : ''}',
                    style: TextStyle(color: context.gt.onSurface)),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.close, color: context.gt.onSurfaceMuted),
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
              Text('Posting as ',
                  style: TextStyle(color: context.gt.onSurfaceMuted)),
              Text(widget.authorAlias,
                  style: TextStyle(
                      color: context.gt.accent, fontWeight: FontWeight.bold)),
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
            Text(_error!, style: TextStyle(color: context.gt.danger)),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              if (showToolbar) ...[
                IconButton(
                  onPressed: _busy ? null : _pickImage,
                  icon: const Icon(Icons.image_outlined),
                  color: context.gt.accent,
                  tooltip: 'Add photo',
                ),
                IconButton(
                  onPressed: _busy ? null : () => _pickVideoMenu(context),
                  icon: const Icon(Icons.videocam_outlined),
                  color: context.gt.accent,
                  tooltip: 'Add video',
                ),
                IconButton(
                  onPressed: _busy ? null : _toggleRecording,
                  icon: const Icon(Icons.mic_none),
                  color: context.gt.accent,
                  tooltip: 'Record voice',
                ),
              ],
              const Spacer(),
              Expanded(
                child: FilledButton(
                  onPressed: (_busy || _recording) ? null : _submit,
                  style: FilledButton.styleFrom(backgroundColor: context.gt.accent),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: _busy
                        ? SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: context.gt.onAccent),
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
              leading: Icon(Icons.video_library_outlined, color: context.gt.accent),
              title: const Text('Choose a video'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            ListTile(
              leading: Icon(Icons.videocam_outlined, color: context.gt.accent),
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
          .select(
              'id, parent_comment_id, author_alias, type, body, created_at, is_mine')
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
          SnackBar(content: Text('Could not spill: ${e.message}')),
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
        backgroundColor: context.gt.accent,
        foregroundColor: context.gt.onAccent,
        title: const Text('The Tea'),
      ),
      body: Column(
        children: [
          // The post being replied to.
          Container(
            width: double.infinity,
            color: context.gt.accentSoft,
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.postAlias,
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: context.gt.accent)),
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
                      child: Text('No tea yet. Spill something ☕'));
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
                              Padding(
                                padding: EdgeInsets.only(right: 8, top: 2),
                                child: Icon(Icons.subdirectory_arrow_right,
                                    size: 16, color: context.gt.onSurfaceFaint),
                              ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          c['author_alias'] ?? 'anon',
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: context.gt.accent),
                                        ),
                                      ),
                                      // Can only report a comment that
                                      // isn't mine and has a real id.
                                      if (c['id'] != null && c['is_mine'] != true)
                                        InkWell(
                                          onTap: () => showReportSheet(
                                            context,
                                            targetType: 'COMMENT',
                                            targetId: c['id'] as String,
                                          ),
                                          child: Padding(
                                            padding: EdgeInsets.all(4),
                                            child: Icon(Icons.flag_outlined,
                                                size: 16, color: context.gt.onSurfaceFaint),
                                          ),
                                        ),
                                    ],
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
                                          foregroundColor: context.gt.onSurfaceMuted,
                                        ),
                                        onPressed: () => _startReply(c),
                                        child: const Text('Spill More'),
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
              color: context.gt.accentSoft,
              padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Spilling more to ${_replyingTo!['author_alias'] ?? 'anon'}',
                      style: TextStyle(
                          color: context.gt.accent, fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close, size: 18),
                    tooltip: 'Cancel',
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
                            ? 'Join to spill'
                            : (_replyingTo != null
                                ? 'Spill more…'
                                : 'Spill the tea…'),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  IconButton(
                    color: context.gt.accent,
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

// ============================================================
// Moderation queue — open reports for groups I moderate
// ============================================================
// Reached from the feed's shield icon (OWNER/ADMIN only). Lists open
// reports from fn_moderation_queue with the evidence snapshot, and lets
// a moderator remove the content, dismiss, or ban the author — all via
// the SECURITY DEFINER RPCs, which re-check the moderator role.
class ModerationQueueScreen extends StatefulWidget {
  const ModerationQueueScreen({super.key, required this.groupName});

  final String groupName;

  @override
  State<ModerationQueueScreen> createState() => _ModerationQueueScreenState();
}

class _ModerationQueueScreenState extends State<ModerationQueueScreen> {
  List<Map<String, dynamic>>? _reports; // null = loading
  Object? _error;
  bool _acting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await supabase.rpc('fn_moderation_queue');
      if (mounted) {
        setState(() {
          _reports = (rows as List).cast<Map<String, dynamic>>();
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _action(
      Map<String, dynamic> report, String action, String verb) async {
    if (_acting) return;
    setState(() => _acting = true);
    try {
      await supabase.rpc('fn_action_report', params: {
        'p_report_id': report['id'],
        'p_action': action,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Report $verb.')),
        );
      }
      await _load();
    } on PostgrestException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Action failed: ${e.message}')),
        );
      }
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: context.gt.accent,
        foregroundColor: context.gt.onAccent,
        title: Text('Moderation · ${widget.groupName}'),
      ),
      body: Builder(
        builder: (context) {
          if (_error != null) return Center(child: Text('Error: $_error'));
          final reports = _reports;
          if (reports == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (reports.isEmpty) {
            return const Center(child: Text('No open reports. All clear 🎉'));
          }
          return RefreshIndicator(
            onRefresh: _load,
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: reports.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) =>
                  _ReportCard(report: reports[i], acting: _acting, onAction: _action),
            ),
          );
        },
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.report,
    required this.acting,
    required this.onAction,
  });

  final Map<String, dynamic> report;
  final bool acting;
  final Future<void> Function(Map<String, dynamic>, String, String) onAction;

  @override
  Widget build(BuildContext context) {
    final reason = report['reason'] as String?;
    final reasonLabel = _reportReasons[reason] ?? reason ?? 'Report';
    final targetType = (report['target_type'] as String?) ?? '';
    final details = report['details'] as String?;
    final evidence = report['evidence'] as Map<String, dynamic>?;
    final snapshotBody = evidence?['body'] as String?;
    final snapshotAlias = evidence?['author_alias'] as String?;
    final status = report['status'] as String?;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Chip(
                  visualDensity: VisualDensity.compact,
                  backgroundColor: context.gt.accentSoft,
                  side: BorderSide.none,
                  label: Text('$targetType · $reasonLabel',
                      style: TextStyle(color: context.gt.accent, fontWeight: FontWeight.w600)),
                ),
                const Spacer(),
                if (status == 'UNDER_REVIEW')
                  Text('under review',
                      style: TextStyle(color: context.gt.onSurfaceMuted, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 8),
            // Evidence snapshot captured at report time.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: context.gt.surfaceSunken,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (snapshotAlias != null)
                    Text(snapshotAlias,
                        style: TextStyle(
                            fontWeight: FontWeight.bold, color: context.gt.onSurface)),
                  const SizedBox(height: 2),
                  Text(
                    snapshotBody?.isNotEmpty == true
                        ? snapshotBody!
                        : '[media or empty — captured at report time]',
                    style: TextStyle(color: context.gt.onSurfaceMuted),
                  ),
                ],
              ),
            ),
            if (details != null && details.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Reporter note: $details',
                  style: TextStyle(
                      fontStyle: FontStyle.italic, color: context.gt.onSurfaceMuted)),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                FilledButton.tonalIcon(
                  onPressed: acting
                      ? null
                      : () => onAction(report, 'CONTENT_REMOVED', 'content removed'),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Remove content'),
                ),
                FilledButton.tonalIcon(
                  onPressed: acting
                      ? null
                      : () => onAction(report, 'USER_BANNED', 'user banned'),
                  icon: const Icon(Icons.block, size: 18),
                  label: const Text('Ban author'),
                ),
                TextButton(
                  onPressed:
                      acting ? null : () => onAction(report, 'CONTENT_KEPT', 'dismissed'),
                  child: const Text('Dismiss'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// Account settings — delete my account (DPDP erasure)
// ============================================================
// Calls fn_erase_user, which scrubs PII, content-strips the user's posts
// and comments, and returns the Storage blobs to purge. We then delete
// those blobs through the Storage API (the DB can't — Supabase's
// protect_delete guard), and sign out.
class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  bool _busy = false;
  final _confirmController = TextEditingController();

  @override
  void dispose() {
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _erase() async {
    setState(() => _busy = true);
    try {
      final uid = supabase.auth.currentUser!.id;
      final result = await supabase.rpc('fn_erase_user', params: {'p_user_id': uid});

      // Purge the returned Storage blobs via the Storage API, grouped by
      // bucket. The DELETE storage policies key off authorship, which is
      // still valid in this final authenticated moment.
      final objects = (result?['storage_objects'] as List?) ?? const [];
      final byBucket = <String, List<String>>{};
      for (final o in objects.cast<Map<String, dynamic>>()) {
        final bucket = o['bucket'] as String?;
        final path = o['path'] as String?;
        if (bucket != null && path != null) {
          (byBucket[bucket] ??= []).add(path);
        }
      }
      for (final entry in byBucket.entries) {
        try {
          await supabase.storage.from(entry.key).remove(entry.value);
        } catch (_) {
          // Best effort — the orphan-sweep job cleans up any stragglers.
        }
      }

      await supabase.auth.signOut();
      // AuthGate reacts to sign-out and returns to the login screen.
    } on PostgrestException catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete account: ${e.message}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final canDelete = _confirmController.text.trim().toUpperCase() == 'DELETE';
    return Scaffold(
      appBar: AppBar(
        backgroundColor: context.gt.accent,
        foregroundColor: context.gt.onAccent,
        title: const Text('Delete account'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('This permanently erases your account.',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            Text(
              'We will scrub your profile, remove your posts, comments and '
              'uploaded media, and drop you from every group. Reports you '
              'filed stay open for moderators, but your personal details are '
              'wiped. This cannot be undone.',
              style: TextStyle(color: context.gt.onSurfaceMuted),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _confirmController,
              enabled: !_busy,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Type DELETE to confirm',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: context.gt.danger),
              onPressed: (_busy || !canDelete) ? null : _erase,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: _busy
                    ? SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: context.gt.onAccent),
                      )
                    : const Text('Delete my account'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
