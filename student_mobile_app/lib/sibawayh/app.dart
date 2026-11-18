// SPDX-FileCopyrightText: 2026 Ahmed Elwakeel
// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

import 'store.dart';
import 'admin.dart';
import 'player.dart';
import 'quizzes.dart';

Color brandColor(String? value, Color fallback) {
  final n = int.tryParse((value ?? '').replaceFirst('#', ''), radix: 16);
  return n == null ? fallback : Color(0xFF000000 | n);
}

String dateLabel(dynamic value) {
  final s = seconds(value);
  if (s == 0) return 'غير مفعل';
  final d = DateTime.fromMillisecondsSinceEpoch(s * 1000).toLocal();
  return '${d.day}/${d.month}/${d.year} — ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

void message(BuildContext context, Object e) {
  String s = e.toString().replaceFirst('Bad state: ', '');
  if (e is FirebaseAuthException) {
    s = switch (e.code) {
      'invalid-credential' ||
      'wrong-password' ||
      'user-not-found' => 'الإيميل أو كلمة المرور غير صحيحة',
      'email-already-in-use' => 'الإيميل مسجل بالفعل',
      'weak-password' => 'استخدم كلمة مرور أقوى',
      'network-request-failed' => 'راجع اتصال الإنترنت',
      _ => 'تعذر إتمام الطلب. راجع البيانات والاتصال.',
    };
  } else if (e is FirebaseException && e.code == 'permission-denied') {
    s = 'الاشتراك غير مفعل، أو لا توجد صلاحية لهذا الإجراء.';
  }
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
}

Future<void> contact(
  SibStore store,
  BuildContext context, {
  String? course,
}) async {
  final number = text(store.brand, 'whatsapp');
  if (!RegExp(r'^[1-9][0-9]{7,14}$').hasMatch(number)) {
    message(context, 'رقم واتساب لم يضف بعد من حساب المالك');
    return;
  }
  final p = store.profile ?? {};
  final uri = Uri.https('wa.me', '/$number', {
    'text':
        'طلب تفعيل / تجديد سيبويه\nالاسم: ${text(p, 'name')}\nالإيميل: ${text(p, 'email')}\nالصف: ${text(p, 'grade')}\nالكورس: ${course ?? 'الاشتراك الدراسي — ٣٠ يومًا'}\nالكود: ${store.studentCode}',
  });
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
      context.mounted)
    message(context, 'تعذر فتح واتساب');
}

class SibImage extends StatelessWidget {
  const SibImage(
    this.value, {
    super.key,
    this.height = 230,
    this.fit = BoxFit.cover,
  });
  final String value;
  final double height;
  final BoxFit fit;
  @override
  Widget build(BuildContext context) {
    final fallback = Image.asset(
      'assets/sibawayh_brand.jpg',
      height: height,
      width: double.infinity,
      fit: fit,
      alignment: Alignment.topCenter,
    );
    if (value.isEmpty) return fallback;
    if (value.startsWith('data:image/')) {
      try {
        return Image.memory(
          base64Decode(value.split(',').last),
          height: height,
          width: double.infinity,
          fit: fit,
          errorBuilder: (_, e, s) => fallback,
        );
      } catch (_) {
        return fallback;
      }
    }
    final u = Uri.tryParse(value);
    if (u?.scheme != 'https') return fallback;
    return Image.network(
      value,
      height: height,
      width: double.infinity,
      fit: fit,
      alignment: Alignment.topCenter,
      errorBuilder: (_, e, s) => fallback,
    );
  }
}

class SibawayhApp extends StatelessWidget {
  const SibawayhApp({super.key, required this.store});
  final SibStore store;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: store,
    builder: (context, _) => MaterialApp(
      navigatorObservers: store.ready
          ? [FirebaseAnalyticsObserver(analytics: FirebaseAnalytics.instance)]
          : const [],
      title: text(store.brand, 'title', 'سيبويه'),
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: brandColor(
            text(store.brand, 'gold'),
            const Color(0xFFC6A15B),
          ),
        ),
        scaffoldBackgroundColor: brandColor(
          text(store.brand, 'paper'),
          const Color(0xFFFAF7F0),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF171615),
          foregroundColor: Color(0xFFE8C581),
          centerTitle: false,
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFFFFFDF8),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFFE6DCCB)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFFFFDF8),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(13)),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: brandColor(
              text(store.brand, 'gold'),
              const Color(0xFFC6A15B),
            ),
            foregroundColor: const Color(0xFF211A10),
            minimumSize: const Size(0, 50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(13),
            ),
          ),
        ),
      ),
      home: store.profile?['blocked'] == true
          ? BlockedScreen(store: store)
          : store.needsProfile
          ? CompleteProfileScreen(store: store)
          : store.signedIn
          ? StudentShell(store: store)
          : AuthScreen(store: store),
    ),
  );
}

class BlockedScreen extends StatelessWidget {
  const BlockedScreen({super.key, required this.store});
  final SibStore store;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('سيبويه')),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 64),
            const SizedBox(height: 20),
            const Text('الحساب موقوف. تواصل مع الإدارة.'),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => contact(store, context),
              child: const Text('تواصل عبر واتساب'),
            ),
            TextButton(
              onPressed: store.logout,
              child: const Text('تسجيل الخروج'),
            ),
          ],
        ),
      ),
    ),
  );
}

class CompleteProfileScreen extends StatefulWidget {
  const CompleteProfileScreen({super.key, required this.store});
  final SibStore store;
  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  final formKey = GlobalKey<FormState>();
  final name = TextEditingController(), phone = TextEditingController();
  String? grade;
  bool busy = false;

  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!formKey.currentState!.validate()) return;
    setState(() => busy = true);
    try {
      await widget.store.completeProfile(
        name.text,
        phone.text,
        grade ?? widget.store.grades.first,
      );
    } catch (e) {
      if (mounted) message(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    return Scaffold(
      appBar: AppBar(
        title: const Text('استكمال الحساب'),
        actions: [
          TextButton(
            onPressed: busy ? null : store.logout,
            child: const Text(
              'خروج',
              style: TextStyle(color: Color(0xFFE8C581)),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Form(
                key: formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(
                      Icons.manage_accounts_outlined,
                      size: 72,
                      color: Color(0xFF9C712E),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'حسابك موجود',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'نحتاج استكمال بيانات الطالب مرة واحدة لفتح المنصة.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 28),
                    TextFormField(
                      controller: name,
                      decoration: const InputDecoration(
                        labelText: 'الاسم بالكامل',
                      ),
                      validator: (value) => (value ?? '').trim().length < 3
                          ? 'اكتب الاسم بالكامل'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: phone,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'رقم الموبايل',
                      ),
                      validator: (value) => RegExp(
                        r'^\+?[0-9]{8,15}$',
                      ).hasMatch((value ?? '').trim())
                          ? null
                          : 'رقم الهاتف بالأرقام الإنجليزية',
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: grade ?? store.grades.first,
                      decoration: const InputDecoration(
                        labelText: 'الصف الدراسي',
                      ),
                      items: store.grades
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(value),
                            ),
                          )
                          .toList(),
                      onChanged: busy ? null : (value) => grade = value,
                    ),
                    const SizedBox(height: 22),
                    FilledButton(
                      onPressed: busy ? null : submit,
                      child: Text(busy ? 'جارٍ الحفظ…' : 'حفظ ودخول'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.store});
  final SibStore store;
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool form = false, register = true, busy = false, obscure = true;
  final key = GlobalKey<FormState>();
  final name = TextEditingController(),
      phone = TextEditingController(),
      email = TextEditingController(),
      password = TextEditingController();
  String? grade;
  @override
  void dispose() {
    for (final c in [name, phone, email, password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> submit() async {
    if (!key.currentState!.validate()) return;
    setState(() => busy = true);
    try {
      if (register) {
        await widget.store.register(
          name.text,
          phone.text,
          grade ?? widget.store.grades.first,
          email.text,
          password.text,
        );
      } else {
        await widget.store.login(email.text, password.text);
      }
    } catch (e) {
      if (mounted) message(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget field(
    TextEditingController c,
    String label, {
    bool secret = false,
    TextInputType? type,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      controller: c,
      obscureText: secret && obscure,
      keyboardType: type,
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: secret
            ? IconButton(
                onPressed: () => setState(() => obscure = !obscure),
                icon: Icon(obscure ? Icons.visibility_off : Icons.visibility),
              )
            : null,
      ),
      validator: (v) {
        final t = (v ?? '').trim();
        if (t.isEmpty) return 'الحقل مطلوب';
        if (c == email && !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(t))
          return 'راجع البريد الإلكتروني';
        if (c == phone && !RegExp(r'^\+?[0-9]{8,15}$').hasMatch(t))
          return 'رقم الهاتف بالأرقام الإنجليزية';
        if (c == password && register && t.length < 10)
          return '١٠ أحرف على الأقل';
        return null;
      },
    ),
  );
  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    return Scaffold(
      body: SafeArea(
        child: form
            ? SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Form(
                      key: key,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Align(
                            alignment: Alignment.centerRight,
                            child: IconButton(
                              onPressed: () => setState(() => form = false),
                              icon: const Icon(Icons.arrow_back),
                            ),
                          ),
                          Text(
                            text(s.brand, 'title'),
                            style: const TextStyle(
                              fontSize: 42,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF9C712E),
                            ),
                          ),
                          Text(text(s.brand, 'subtitle')),
                          const SizedBox(height: 25),
                          Text(
                            register ? 'إنشاء حساب' : 'تسجيل الدخول',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 22),
                          if (register) ...[
                            field(name, 'الاسم بالكامل'),
                            field(
                              phone,
                              'رقم الموبايل',
                              type: TextInputType.phone,
                            ),
                            DropdownButtonFormField<String>(
                              initialValue: grade ?? s.grades.first,
                              decoration: const InputDecoration(
                                labelText: 'الصف الدراسي',
                              ),
                              items: s.grades
                                  .map(
                                    (g) => DropdownMenuItem(
                                      value: g,
                                      child: Text(g),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) => grade = v,
                            ),
                            const SizedBox(height: 16),
                          ],
                          field(
                            email,
                            'البريد الإلكتروني',
                            type: TextInputType.emailAddress,
                          ),
                          field(password, 'كلمة المرور', secret: true),
                          if (s.setupError != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Text(
                                s.setupError!,
                                style: const TextStyle(color: Colors.brown),
                              ),
                            ),
                          FilledButton(
                            onPressed: busy ? null : submit,
                            child: Text(
                              busy
                                  ? 'جارٍ التنفيذ…'
                                  : register
                                  ? 'إنشاء الحساب'
                                  : 'دخول',
                            ),
                          ),
                          TextButton(
                            onPressed: busy
                                ? null
                                : () => setState(() => register = !register),
                            child: Text(
                              register
                                  ? 'عندك حساب؟ تسجيل الدخول'
                                  : 'طالب جديد؟ أنشئ حسابك',
                            ),
                          ),
                          if (!register)
                            TextButton(
                              onPressed: () async {
                                try {
                                  await s.resetPassword(email.text);
                                  if (context.mounted)
                                    message(
                                      context,
                                      'لو البريد مسجل، هتوصلك رسالة استعادة كلمة المرور.',
                                    );
                                } catch (e) {
                                  if (context.mounted) message(context, e);
                                }
                              },
                              child: const Text('نسيت كلمة المرور؟'),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              )
            : LayoutBuilder(
                builder: (context, c) => SingleChildScrollView(
                  child: Column(
                    children: [
                      ColoredBox(
                        color: const Color(0xFF111111),
                        child: SibImage(
                          text(s.brand, 'welcomeImage'),
                          height: c.maxHeight * .62,
                          fit: BoxFit.contain,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(25, 22, 25, 28),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              text(s.brand, 'title'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 44,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF96702D),
                              ),
                            ),
                            Text(
                              text(s.brand, 'welcome'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(height: 1.7),
                            ),
                            const SizedBox(height: 22),
                            FilledButton(
                              onPressed: () => setState(() {
                                form = true;
                                register = true;
                              }),
                              child: const Text('ابدأ رحلتك'),
                            ),
                            TextButton(
                              onPressed: () => setState(() {
                                form = true;
                                register = false;
                              }),
                              child: const Text('تسجيل الدخول'),
                            ),
                            if (!s.ready)
                              const Text(
                                'معاينة قبل ربط Firebase',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.brown,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

class StudentShell extends StatefulWidget {
  const StudentShell({super.key, required this.store});
  final SibStore store;
  @override
  State<StudentShell> createState() => _StudentShellState();
}

class _StudentShellState extends State<StudentShell> {
  int tab = 0;
  int refresh = 0;
  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    return Scaffold(
      appBar: AppBar(
        title: Text(text(s.brand, 'title')),
        actions: [
          if (s.owner)
            IconButton(
              tooltip: 'إدارة المنصة',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => AdminDashboard(store: s),
                ),
              ),
              icon: const Icon(Icons.admin_panel_settings_outlined),
            ),
        ],
      ),
      body: tab == 4
          ? _account(context, s)
          : tab == 3
          ? StudentQuizzes(store: s)
          : FutureBuilder<List<RowData>>(
              key: ValueKey('$tab-$refresh'),
              future: s.courses(),
              builder: (context, snap) {
                if (snap.hasError)
                  return Center(
                    child: Text('تعذر تحميل الدروس. ${snap.error}'),
                  );
                if (!snap.hasData)
                  return const Center(child: CircularProgressIndicator());
                final items = snap.data!
                    .where(
                      (c) => tab == 2
                          ? c['kind'] == 'develop'
                          : tab == 1
                          ? c['kind'] == 'school'
                          : true,
                    )
                    .toList();
                return RefreshIndicator(
                  onRefresh: () async => setState(() => refresh++),
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      if (tab == 0) ...[
                        Text(
                          'أهلًا، ${text(s.profile ?? {}, 'name').split(' ').first}',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        Text(text(s.profile ?? {}, 'grade')),
                        const SizedBox(height: 20),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(22),
                          child: SibImage(
                            text(s.brand, 'homeImage'),
                            height: 260,
                            fit: BoxFit.contain,
                          ),
                        ),
                        const SizedBox(height: 18),
                        if (text(s.brand, 'announcement').isNotEmpty)
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(18),
                              child: Text(
                                text(s.brand, 'announcement'),
                                style: const TextStyle(height: 1.8),
                              ),
                            ),
                          ),
                        const SizedBox(height: 15),
                      ],
                      Text(
                        tab == 2
                            ? 'طور نفسك'
                            : tab == 1
                            ? 'دروسي'
                            : 'كورساتك',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      if (items.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(35),
                          child: Text('لم تُضف كورسات منشورة بعد.'),
                        ),
                      for (final course in items)
                        CourseCard(store: s, course: course),
                    ],
                  ),
                );
              },
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            label: 'الرئيسية',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            label: 'دروسي',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            label: 'طور نفسك',
          ),
          NavigationDestination(
            icon: Icon(Icons.assignment_outlined),
            label: 'اختباراتي',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            label: 'حسابي',
          ),
        ],
      ),
    );
  }

  Widget _account(BuildContext context, SibStore s) => ListView(
    padding: const EdgeInsets.all(22),
    children: [
      Text('حسابي', style: Theme.of(context).textTheme.headlineMedium),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                text(s.profile ?? {}, 'name'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 10),
              Text(text(s.profile ?? {}, 'email')),
              Text(text(s.profile ?? {}, 'phone')),
              Text(text(s.profile ?? {}, 'grade')),
              const SizedBox(height: 12),
              SelectableText(s.studentCode),
            ],
          ),
        ),
      ),
      FilledButton.icon(
        onPressed: () => contact(s, context),
        icon: const Icon(Icons.chat_outlined),
        label: const Text('التفعيل والتجديد عبر واتساب'),
      ),
      const SizedBox(height: 16),
      if (s.owner)
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => AdminDashboard(store: s)),
          ),
          icon: const Icon(Icons.admin_panel_settings),
          label: const Text('السوبر بانل'),
        ),
      TextButton(onPressed: s.logout, child: const Text('تسجيل الخروج')),
    ],
  );
}

class CourseCard extends StatelessWidget {
  const CourseCard({super.key, required this.store, required this.course});
  final SibStore store;
  final RowData course;
  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<DocumentSnapshot<RowData>>(
    stream: store.subscription(course['id']),
    builder: (context, snap) {
      final end = seconds(snap.data?.data()?['expires_at']);
      final active =
          end > DateTime.now().millisecondsSinceEpoch ~/ 1000 || store.owner;
      return Card(
        margin: const EdgeInsets.only(top: 16),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    course['kind'] == 'develop'
                        ? Icons.auto_awesome
                        : Icons.menu_book,
                    color: const Color(0xFF9C712E),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      text(course, 'title'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(text(course, 'description')),
              const SizedBox(height: 12),
              Text(
                active
                    ? 'متاح • ينتهي ${dateLabel(snap.data?.data()?['expires_at'])}'
                    : 'الاشتراك غير مفعل أو انتهى',
                style: TextStyle(
                  color: active ? Colors.green : Colors.brown,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => CourseScreen(store: store, course: course),
                  ),
                ),
                child: const Text('افتح الدروس'),
              ),
              if (!active)
                TextButton(
                  onPressed: () =>
                      contact(store, context, course: text(course, 'title')),
                  child: const Text('تفعيل / تجديد عبر واتساب'),
                ),
            ],
          ),
        ),
      );
    },
  );
}

class CourseScreen extends StatefulWidget {
  const CourseScreen({super.key, required this.store, required this.course});
  final SibStore store;
  final RowData course;
  @override
  State<CourseScreen> createState() => _CourseScreenState();
}

class _CourseScreenState extends State<CourseScreen> {
  String? selected;
  late Future<List<RowData>> items;
  @override
  void initState() {
    super.initState();
    items = widget.store.list(
      'lessons',
      field: 'course_id',
      equalTo: widget.course['id'],
      published: true,
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(text(widget.course, 'title'))),
    body: FutureBuilder<List<RowData>>(
      future: items,
      builder: (context, snap) {
        if (snap.hasError)
          return const Center(child: Text('تعذر تحميل المحاضرات'));
        if (!snap.hasData)
          return const Center(child: CircularProgressIndicator());
        final rows = snap.data!;
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('الكل'),
                  selected: selected == null,
                  onSelected: (_) => setState(() => selected = null),
                ),
                for (final sub in rows.map((r) => text(r, 'subject')).where((s) => s.isNotEmpty).toSet())
                  ChoiceChip(
                    label: Text(sub),
                    selected: selected == sub,
                    onSelected: (_) => setState(() => selected = sub),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            if (rows.isEmpty) const Text('لم تُضف محاضرات بعد'),
            GridView.extent(
              maxCrossAxisExtent: MediaQuery.sizeOf(context).width >= 700 ? 440 : 700,
              mainAxisExtent: 108,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                  for (final lesson in rows.where(
              (r) => selected == null || r['subject'] == selected,
            ))
              Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.all(18),
                  leading: const Icon(
                    Icons.play_circle_outline,
                    size: 36,
                    color: Color(0xFF9C712E),
                  ),
                  title: Text(text(lesson, 'title')),
                  subtitle: Text(text(lesson, 'subject')),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          LessonPlayer(store: widget.store, lesson: lesson),
                    ),
                  ),
                ),
              ),
              ],
            ),
          ],
        );
      },
    ),
  );
}
