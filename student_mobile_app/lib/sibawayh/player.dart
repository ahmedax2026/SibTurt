// SPDX-FileCopyrightText: 2026 Ahmed Elwakeel
// SPDX-License-Identifier: Apache-2.0
import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:universal_youtube_player/universal_youtube_player.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'store.dart';
import 'app.dart';
import 'quizzes.dart';

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
  VoidCallback? pauseYoutube;
  String? youtubeId;
  UniversalYoutubeController? universal;
  StreamSubscription<Duration>? universalProgress;
  double youtubePosition = 0;
  WebViewController? drive;
  Timer? checkTimer, saveTimer, controlsTimer;
  bool controlsVisible = true;
  void scheduleHide() {
    controlsTimer?.cancel();
    controlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && video?.value.isPlaying == true) setState(() => controlsVisible = false);
    });
  }
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
  List<RowData> lessonQuizzes = [];
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
      if (loaded && elapsed.elapsed.inSeconds % ((s.brand['watermarkInterval'] as num?)?.toInt() ?? 7).clamp(3, 20).toInt() == 0 && mounted)
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
    pauseYoutube?.call();
    if (youtubeId != null) { universalProgress?.cancel(); universal?.dispose(); universal = null; pauseYoutube = null; youtubeId = null; loaded = false; }
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
      final profile = widget.store.profile ?? {};
      final phone = text(profile, 'phone');
      final code = widget.store.studentCode;
      final mode = text(widget.store.brand, 'watermarkMode', 'code');
      final identity = switch (mode) {
        'email' => text(profile, 'email', code),
        'phone' => phone.isEmpty ? code : phone,
        'masked' => '$code • …${phone.length > 4 ? phone.substring(phone.length - 4) : phone}',
        _ => code,
      };
      mark = '${identity.isEmpty ? code : identity} • ${playback['id']}';
      if (!widget.store.owner && (expires ?? 0) <= trustedNow())
        throw StateError('انتهى الاشتراك أو لم يُفعّل');
      final resume = await widget.store.db
          .doc('users/${widget.store.uid}/progress/${widget.lesson['id']}')
          .get(const GetOptions(source: Source.server));
      completed = resume.data()?['completed'] == true;
      try {
        final quizzes = await widget.store.list(
          'quizzes',
          field: 'course_id',
          equalTo: widget.lesson['course_id'],
          published: true,
        );
        lessonQuizzes = quizzes
            .where((q) => q['lesson_id'] == widget.lesson['id'])
            .toList();
      } catch (_) {
        lessonQuizzes = [];
      }
      var start = ((resume.data()?['seconds'] as num?) ?? 0).toDouble();
      provider = text(source, 'provider');
      if (!mounted) return;
      if (start >= 5 && provider != 'drive') {
        final saved = Duration(seconds: start.toInt());
        final stamp = '${saved.inHours.toString().padLeft(2, '0')}:${(saved.inMinutes % 60).toString().padLeft(2, '0')}:${(saved.inSeconds % 60).toString().padLeft(2, '0')}';
        final resumePlayback = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            icon: const Icon(Icons.play_circle_outline, color: Color(0xFFC6A15B), size: 48),
            title: const Text('أهلًا بعودتك'),
            content: Text('سبق لك مشاهدة هذا الدرس. آخر موضع: $stamp'),
            actions: [
              OutlinedButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('البدء من الأول'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('استكمال المشاهدة'),
              ),
            ],
          ),
        );
        if (!mounted) return;
        if (resumePlayback == false) start = 0;
      }
      final url = text(source, 'url');
      if (provider == 'youtube') {
        final uri = Uri.tryParse(url);
        final id = uri?.queryParameters['v'] ??
            (uri != null && uri.pathSegments.isNotEmpty ? uri.pathSegments.last : url);
        if (!RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id)) {
          throw StateError('معرف الفيديو غير صحيح');
        }
        youtubeId = id;
        youtubePosition = start;
        final c = UniversalYoutubeController();
        universal = c;
        universalProgress = c.positionStream.listen((p) => youtubePosition = p.inMilliseconds / 1000);
        pauseYoutube = () { c.pause(); };
        await c.load(url, autoPlay: false);
        if (!mounted || universal != c) return;
        if (start > 0) await c.seek(Duration(seconds: start.toInt()));
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
        final uri = provider == 'okru' ? await resolveOk(url) : Uri.tryParse(url);
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
        setState(() => failure = 'تعذر تشغيل الفيديو. تحقق من الاتصال أو تواصل مع الإدارة.');
    } finally {
      opening = false;
      if (mounted) unawaited(enforce());
    }
  }

  bool refreshingOk = false;
  int okRetries = 0;
  static Future<Uri> resolveOk(String link) async {
    final uri = Uri.parse(link);
    final match = RegExp(r'^/video(?:embed)?/(\d+)$').firstMatch(uri.path);
    if (!['ok.ru', 'www.ok.ru', 'm.ok.ru'].contains(uri.host) || match == null) {
      throw StateError('رابط OK.ru غير صحيح');
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.postUrl(Uri.https('www.ok.ru', '/dk', {'cmd': 'videoPlayerMetadata'}));
      req.headers.contentType = ContentType('application', 'x-www-form-urlencoded');
      req.write('mid=${match.group(1)}');
      final res = await req.close().timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) throw StateError('OK.ru unavailable');
      final data = jsonDecode(await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 20)));
      final streams = data['videos'] as List? ?? [];
      const ranks = ['mobile', 'lowest', 'low', 'sd', 'hd', 'full', 'quad', 'ultra'];
      final candidates = streams.whereType<Map>().where((v) {
        final u = Uri.tryParse(v['url']?.toString() ?? '');
        return u?.scheme == 'https' && (u!.host.endsWith('.okcdn.ru') || u.host.endsWith('.vkuser.net'));
      }).toList();
      candidates.sort((a,b) => ranks.indexOf(b['name'].toString()).compareTo(ranks.indexOf(a['name'].toString())));
      if (candidates.isEmpty) throw StateError('No available stream');
      return Uri.parse(candidates.first['url'].toString());
    } finally {
      client.close(force: true);
    }
  }

  Future<void> refreshOk() async {
    if (refreshingOk || okRetries >= 2 || !mounted || reason.isNotEmpty) return;
    refreshingOk = true;
    okRetries++;
    final old = video;
    VideoPlayerController? next;
    try {
      final position = old?.value.position ?? Duration.zero;
      next = VideoPlayerController.networkUrl(await resolveOk(text(source, 'url')));
      await next.initialize();
      await next.seekTo(position);
      if (!mounted || reason.isNotEmpty || video != old) return;
      old?.removeListener(onTick);
      video = next;
      next = null;
      video!.addListener(onTick);
      await old?.dispose();
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() => failure = 'تعذر تجديد رابط الفيديو. أعد فتح المحاضرة.');
    } finally {
      await next?.dispose();
      refreshingOk = false;
    }
  }

  void onTick() {
    if (mounted) {
      setState(() {});
      if (provider == 'okru' && video?.value.hasError == true) unawaited(refreshOk());
    }
  }

  Future<void> save() async {
    if (!loaded || reason.isNotEmpty || !mounted) return;
    try {
      final position =
          video?.value.position.inSeconds.toDouble() ??
          youtubePosition;
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
    controlsTimer?.cancel();
    subscription?.cancel();
    video?.removeListener(onTick);
    video?.dispose();
    pauseYoutube?.call();
    universalProgress?.cancel();
    universal?.dispose();
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
    if (youtubeId != null)
      return UniversalYoutubePlayer(
        key: ValueKey(youtubeId),
        controller: universal!,
        aspectRatio: 16 / 9,
      );
    if (drive != null)
      return SizedBox(
        height: full ? MediaQuery.sizeOf(context).height : MediaQuery.sizeOf(context).width * 9 / 16,
        child: WebViewWidget(controller: drive!),
      );
    final c = video;
    if (c == null) return const SizedBox.shrink();
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: LayoutBuilder(builder: (context, constraints) {
        final compact = constraints.maxWidth < 420;
        final duration = c.value.duration.inMilliseconds;
        final position = c.value.position.inMilliseconds.clamp(0, max(0, duration)).toInt();
        String time(int ms) {
          final seconds = ms ~/ 1000;
          return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: Colors.black, child: Center(child: AspectRatio(aspectRatio: c.value.aspectRatio, child: VideoPlayer(c)))),
            IgnorePointer(child: AnimatedAlign(
              duration: const Duration(milliseconds: 500),
              alignment: markAlignment,
              child: Text(mark, textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withOpacity(((widget.store.brand['watermarkOpacity'] as num?)?.toDouble() ?? .55).clamp(.25, .85).toDouble()), fontSize: ((widget.store.brand['watermarkSize'] as num?)?.toDouble() ?? 12).clamp(9, 24).toDouble(), shadows: const [Shadow(color: Colors.black, blurRadius: 3)])),
            )),
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () { setState(() => controlsVisible = !controlsVisible); if (controlsVisible) scheduleHide(); },
            ),
            if (controlsVisible) ...[
              Center(child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(tooltip: 'رجوع 10 ثوانٍ', color: Colors.white, iconSize: 30, onPressed: () { c.seekTo(Duration(milliseconds: max(0, position - 10000))); scheduleHide(); }, icon: const Icon(Icons.replay_10)),
                  const SizedBox(width: 12),
                  IconButton.filled(tooltip: 'تشغيل أو إيقاف', style: IconButton.styleFrom(backgroundColor: const Color(0xBB000000), foregroundColor: Colors.white), iconSize: 40, onPressed: () { c.value.isPlaying ? c.pause() : c.play(); scheduleHide(); }, icon: Icon(c.value.isPlaying ? Icons.pause : Icons.play_arrow)),
                  const SizedBox(width: 12),
                  IconButton(tooltip: 'تقديم 10 ثوانٍ', color: Colors.white, iconSize: 30, onPressed: () { c.seekTo(Duration(milliseconds: min(max(0, duration), position + 10000))); scheduleHide(); }, icon: const Icon(Icons.forward_10)),
                ],
              )),
              Positioned(bottom: 0, left: 0, right: 0, child: Container(
                decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black87])),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(children: [
                  Text(time(position), style: TextStyle(color: Colors.white, fontSize: compact ? 10 : 12)),
                  Expanded(child: SliderTheme(data: SliderTheme.of(context).copyWith(trackHeight: 2, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5), activeTrackColor: const Color(0xFFE8C581), thumbColor: const Color(0xFFE8C581)), child: Slider(value: position.toDouble(), max: max(1, duration).toDouble(), onChanged: (v) { c.seekTo(Duration(milliseconds: v.toInt())); scheduleHide(); }))),
                  Text(time(duration), style: TextStyle(color: Colors.white, fontSize: compact ? 10 : 12)),
                  PopupMenuButton<double>(tooltip: 'سرعة التشغيل', onSelected: (speed) { c.setPlaybackSpeed(speed); scheduleHide(); }, itemBuilder: (_) => [for (final speed in [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]) PopupMenuItem(value: speed, child: Text('${speed}x'))], child: Padding(padding: const EdgeInsets.all(8), child: Text('${c.value.playbackSpeed}x', style: const TextStyle(color: Colors.white)))),
                  IconButton(color: Colors.white, tooltip: 'ملء الشاشة', onPressed: toggleFull, icon: Icon(full ? Icons.fullscreen_exit : Icons.fullscreen)),
                ]),
              )),
            ],
          ],
        );
      }),
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
              const SizedBox(height: 15),
              Text(
                text(widget.lesson, 'title'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 15),
              Wrap(
                spacing: 10,
                children: [
                  if (youtubeId != null || drive != null)
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
                            if (context.mounted)
                              message(context, 'تم حفظ إتمام الدرس');
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
              const SizedBox(height: 20),
              Text(
                'اختبار المحاضرة',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (lessonQuizzes.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('لا يوجد اختبار لهذه المحاضرة حاليًا.'),
                )
              else
                for (final quiz in lessonQuizzes)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.quiz_outlined),
                      title: Text(text(quiz, 'title')),
                      subtitle: Text(
                        '${quiz['kind'] == 'homework' ? 'واجب' : 'اختبار'} • ${quiz['time_minutes'] == 0 ? 'بدون توقيت' : '${quiz['time_minutes']} دقيقة'}',
                      ),
                      trailing: const Icon(Icons.chevron_left),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              TakeQuiz(store: widget.store, quiz: quiz),
                        ),
                      ),
                    ),
                  ),
              const SizedBox(height: 20),
              Text(
                'ملزمة المحاضرة',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (text(source, 'attachment').isNotEmpty)
                OutlinedButton.icon(
                  onPressed: () async {
                    widget.store.track('pdf_open', {
                      'course_id': '${widget.lesson['course_id']}',
                      'lesson_id': '${widget.lesson['id']}',
                    });
                    await launchUrl(
                      Uri.parse(text(source, 'attachment')),
                      mode: LaunchMode.externalApplication,
                    );
                  },
                  icon: const Icon(Icons.description_outlined),
                  label: const Text('فتح / تحميل ملف PDF'),
                ),
              if (text(source, 'attachment').isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('لا توجد ملزمة PDF لهذه المحاضرة حاليًا.'),
                ),
              if (youtubeId != null || drive != null)
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
