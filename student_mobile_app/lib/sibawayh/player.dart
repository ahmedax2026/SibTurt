// SPDX-FileCopyrightText: 2026 Ahmed Elwakeel
// SPDX-License-Identifier: Apache-2.0
import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'store.dart';
import 'app.dart';

class LessonPlayer extends StatefulWidget {
  const LessonPlayer({super.key, required this.store, required this.lesson});
  final SibStore store;
  final RowData lesson;
  @override
  State<LessonPlayer> createState() => _LessonPlayerState();
}

class _LessonPlayerState extends State<LessonPlayer>
    with WidgetsBindingObserver {
  static const channel = MethodChannel('sibawayh/security');
  VideoPlayerController? video;
  YoutubePlayerController? youtube;
  WebViewController? drive;
  Timer? checkTimer, saveTimer;
  StreamSubscription<DocumentSnapshot<RowData>>? subscription;
  bool opening = false,
      loaded = false,
      full = false,
      completed = false,
      pausedForBackground = false;
  String reason = 'جارٍ التحقق من المشاهدة…',
      failure = '',
      mark = '',
      provider = '';
  String? sessionUid;
  int? expires;
  int anchor = 0;
  final elapsed = Stopwatch();
  Alignment markAlignment = const Alignment(-.6, -.5);
  RowData source = {};
  @override
  void initState() {
    super.initState();
    sessionUid = widget.store.uid;
    WidgetsBinding.instance.addObserver(this);
    checkTimer = Timer.periodic(const Duration(seconds: 1), (_) => enforce());
    saveTimer = Timer.periodic(const Duration(seconds: 20), (_) => save());
    unawaited(enforce());
    subscription = widget.store.subscription(widget.lesson['course_id']).listen(
      (doc) {
        expires = seconds(doc.data()?['expires_at']);
        unawaited(enforce());
      },
      onError: (Object e) => block('تعذر التحقق من الاشتراك'),
    );
  }

  int trustedNow() => anchor == 0 ? 0 : anchor + elapsed.elapsed.inSeconds;
  Future<void> enforce() async {
    if (!mounted) return;
    final s = widget.store;
    if (s.uid != sessionUid ||
        !s.deviceVerified ||
        s.profile?['blocked'] == true) {
      block('الحساب موقوف أو انتهت جلسة الدخول');
      return;
    }
    if (!s.owner && expires != null && expires! <= trustedNow()) {
      block('انتهى الاشتراك. تواصل مع الإدارة للتجديد.');
      return;
    }
    try {
      final state = await channel.invokeMapMethod<String, dynamic>('status');
      if (!mounted) return;
      String r = '';
      if (s.brand['blockVpn'] != false && state?['vpn'] == true)
        r = 'أوقف VPN وأعد المحاولة';
      if (s.brand['blockProxy'] != false && state?['proxy'] == true)
        r = 'أوقف البروكسي وأدوات فحص الاتصال';
      if (s.brand['requireHeadphones'] != false && state?['headphones'] != true)
        r = 'وصّل سماعة سلك أو بلوتوث لمشاهدة الدرس';
      if (r.isNotEmpty) {
        block(r);
        return;
      }
      if (pausedForBackground) return;
      if (reason.isNotEmpty && mounted) setState(() => reason = '');
      if (!loaded && !opening && failure.isEmpty) await open();
      if (loaded && elapsed.elapsed.inSeconds % 7 == 0 && mounted)
        setState(
          () => markAlignment = Alignment(
            Random().nextDouble() * 1.2 - .6,
            Random().nextDouble() * 1.2 - .6,
          ),
        );
    } on PlatformException {
      block('تعذر فحص حماية الجهاز؛ أعد فتح التطبيق');
    } on MissingPluginException {
      block('فحص المشاهدة متاح في تطبيق أندرويد فقط');
    }
  }

  void block(String value) {
    if (!mounted) return;
    video?.pause();
    youtube?.pauseVideo();
    if (drive != null) {
      drive!.loadRequest(Uri.parse('about:blank'));
      drive = null;
      loaded = false;
    }
    if (reason != value) {
      setState(() {
        reason = value;
        full = false;
      });
      unawaited(
        SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]),
      );
    }
  }

  Future<void> open() async {
    opening = true;
    try {
      source = await widget.store.source(widget.lesson['id']);
      final playback = await widget.store.startPlayback(
        widget.lesson['id'],
        widget.lesson['course_id'],
      );
      anchor = seconds(playback['created_at']);
      elapsed.start();
      mark = '${widget.store.studentCode} • ${playback['id']}';
      if (!widget.store.owner && (expires ?? 0) <= trustedNow())
        throw StateError('انتهى الاشتراك أو لم يُفعّل');
      final resume = await widget.store.db
          .doc('users/${widget.store.uid}/progress/${widget.lesson['id']}')
          .get(const GetOptions(source: Source.server));
      completed = resume.data()?['completed'] == true;
      final start = ((resume.data()?['seconds'] as num?) ?? 0).toDouble();
      provider = text(source, 'provider');
      final url = text(source, 'url');
      if (provider == 'youtube') {
        youtube = YoutubePlayerController(
          params: const YoutubePlayerParams(
            showControls: true,
            showFullscreenButton: false,
          ),
        )..loadVideo(url);
      } else if (provider == 'drive') {
        final match = RegExp(r'/file/d/([A-Za-z0-9_-]+)').firstMatch(url);
        final id = match?.group(1) ?? Uri.tryParse(url)?.queryParameters['id'];
        if (id == null) throw StateError('رابط Google Drive غير صحيح');
        drive = WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setNavigationDelegate(
            NavigationDelegate(
              onNavigationRequest: (request) {
                final u = Uri.tryParse(request.url);
                return u?.scheme == 'https' &&
                        (u!.host == 'drive.google.com' ||
                            u.host == 'accounts.google.com' ||
                            u.host.endsWith('.googleusercontent.com'))
                    ? NavigationDecision.navigate
                    : NavigationDecision.prevent;
              },
            ),
          )
          ..loadRequest(Uri.https('drive.google.com', '/file/d/$id/preview'));
      } else {
        final uri = Uri.tryParse(url);
        if (uri?.scheme != 'https')
          throw StateError('الفيديو يحتاج رابط HTTPS صالحًا');
        final c = VideoPlayerController.networkUrl(uri!);
        await c.initialize();
        if (!mounted) {
          await c.dispose();
          return;
        }
        video = c;
        if (start < c.value.duration.inSeconds)
          await c.seekTo(Duration(seconds: start.toInt()));
        c.addListener(onTick);
      }
      if (mounted) {
        loaded = true;
        setState(() {});
      }
    } catch (e) {
      if (mounted)
        setState(() => failure = e.toString().replaceFirst('Bad state: ', ''));
    } finally {
      opening = false;
      if (mounted) unawaited(enforce());
    }
  }

  void onTick() {
    if (mounted) setState(() {});
  }

  Future<void> save() async {
    if (!loaded || reason.isNotEmpty || !mounted) return;
    try {
      final position =
          video?.value.position.inSeconds.toDouble() ??
          (youtube == null ? 0 : await youtube!.currentTime);
      await widget.store.saveProgress(
        widget.lesson['id'],
        widget.lesson['course_id'],
        position,
        completed,
      );
    } catch (_) {
      /* A network failure never grants extra access. Source rules remain authoritative. */
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      pausedForBackground = true;
      block('اضغط متابعة بعد العودة للتطبيق');
    }
  }

  Future<void> toggleFull() async {
    setState(() => full = !full);
    await SystemChrome.setPreferredOrientations(
      full
          ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
          : [DeviceOrientation.portraitUp],
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    checkTimer?.cancel();
    saveTimer?.cancel();
    subscription?.cancel();
    video?.removeListener(onTick);
    video?.dispose();
    youtube?.close();
    elapsed.stop();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  Widget stage() {
    if (failure.isNotEmpty)
      return Padding(
        padding: const EdgeInsets.all(25),
        child: Text(failure, style: const TextStyle(color: Colors.white)),
      );
    if (reason.isNotEmpty)
      return Padding(
        padding: const EdgeInsets.all(25),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.shield_outlined,
              color: Color(0xFFE8C581),
              size: 42,
            ),
            const SizedBox(height: 15),
            Text(
              reason,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, height: 1.8),
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: () {
                pausedForBackground = false;
                unawaited(enforce());
              },
              child: const Text('متابعة'),
            ),
          ],
        ),
      );
    if (!loaded) return const Center(child: CircularProgressIndicator());
    if (youtube != null)
      return YoutubePlayer(controller: youtube!, aspectRatio: 16 / 9);
    if (drive != null)
      return SizedBox(
        height: full ? MediaQuery.sizeOf(context).height : 260,
        child: WebViewWidget(controller: drive!),
      );
    final c = video;
    if (c == null) return const SizedBox.shrink();
    return Stack(
      alignment: Alignment.center,
      children: [
        AspectRatio(aspectRatio: c.value.aspectRatio, child: VideoPlayer(c)),
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 500),
              alignment: markAlignment,
              child: Container(
                color: Colors.black38,
                padding: const EdgeInsets.all(5),
                child: Text(
                  mark,
                  style: const TextStyle(color: Colors.white70, fontSize: 10),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: ColoredBox(
            color: Colors.black54,
            child: Row(
              children: [
                IconButton(
                  onPressed: () => c.value.isPlaying ? c.pause() : c.play(),
                  icon: Icon(
                    c.value.isPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.white,
                  ),
                ),
                Expanded(
                  child: Slider(
                    value: c.value.position.inMilliseconds.toDouble().clamp(
                      0,
                      c.value.duration.inMilliseconds.toDouble(),
                    ),
                    max: max(1, c.value.duration.inMilliseconds.toDouble()),
                    onChanged: (v) =>
                        c.seekTo(Duration(milliseconds: v.toInt())),
                  ),
                ),
                IconButton(
                  onPressed: toggleFull,
                  icon: Icon(
                    full ? Icons.fullscreen_exit : Icons.fullscreen,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: full ? Colors.black : null,
    appBar: full ? null : AppBar(title: Text(text(widget.lesson, 'title'))),
    body: full
        ? Center(child: stage())
        : ListView(
            padding: const EdgeInsets.all(18),
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: ColoredBox(
                  color: Colors.black,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 230),
                    child: stage(),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SelectableText(
                mark,
                textDirection: TextDirection.ltr,
                style: const TextStyle(fontSize: 10, color: Colors.brown),
              ),
              const SizedBox(height: 15),
              Text(
                text(widget.lesson, 'title'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 15),
              Wrap(
                spacing: 10,
                children: [
                  if (youtube != null || drive != null)
                    OutlinedButton.icon(
                      onPressed: toggleFull,
                      icon: const Icon(Icons.fullscreen),
                      label: const Text('ملء الشاشة'),
                    ),
                  FilledButton.icon(
                    onPressed: loaded && reason.isEmpty
                        ? () async {
                            setState(() => completed = true);
                            await save();
                            if (context.mounted) message(context, 'تم حفظ إتمام الدرس');
                          }
                        : null,
                    icon: const Icon(Icons.check_circle_outline),
                    label: Text(
                      completed ? 'أتممت الدرس' : 'أتممت مشاهدة الدرس',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                text(widget.lesson, 'notes'),
                style: const TextStyle(height: 1.9),
              ),
              if (text(source, 'attachment').isNotEmpty)
                OutlinedButton.icon(
                  onPressed: () => launchUrl(
                    Uri.parse(text(source, 'attachment')),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(Icons.description_outlined),
                  label: const Text('ملزمة الدرس'),
                ),
              if (youtube != null || drive != null)
                const Padding(
                  padding: EdgeInsets.only(top: 18),
                  child: Text(
                    'مصدر خارجي مضمّن: كود الجلسة خارج الفيديو، وروابط مقدم الخدمة لا تصبح خاصة بالتطبيق.',
                    style: TextStyle(fontSize: 11, color: Colors.brown),
                  ),
                ),
            ],
          ),
  );
}
