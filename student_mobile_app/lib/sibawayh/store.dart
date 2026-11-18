// SPDX-FileCopyrightText: 2026 Ahmed Elwakeel
// SPDX-License-Identifier: Apache-2.0
import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

typedef RowData = Map<String, dynamic>;
const initialGrades = ['الأول الثانوي', 'الثاني الثانوي', 'الثالث الثانوي'];
const initialSubjects = [
  'النحو',
  'البلاغة',
  'الأدب',
  'النصوص',
  'القراءة',
  'التعبير',
];
const initialBrand = <String, dynamic>{
  'title': 'سيبويه',
  'subtitle': 'منصة اللغة العربية',
  'teacher': 'مصطفى عبدالفضيل الشعار',
  'whatsapp': '',
  'welcome': 'شرح واضح، تدريب مستمر، وخطوة أقرب للتفوق.',
  'announcement': 'أهلًا بك في منصة سيبويه للغة العربية',
  'welcomeImage': '',
  'homeImage': '',
  'gold': '#C6A15B',
  'paper': '#FAF7F0',
  'requireHeadphones': true,
  'blockVpn': true,
  'blockProxy': true,
};
int seconds(dynamic value) => value is Timestamp
    ? value.seconds
    : value is num
    ? value.toInt()
    : 0;
String text(RowData data, String key, [String fallback = '']) =>
    '${data[key] ?? fallback}';

class SibStore extends ChangeNotifier {
  SibStore({this.useNativeFirebase = true});

  final bool useNativeFirebase;
  static const _security = MethodChannel('sibawayh/security');
  FirebaseFirestore? _db;
  FirebaseAuth? _auth;
  bool ready = false, loading = false, owner = false, deviceVerified = false;
  String? setupError;
  String? _deviceId;
  RowData? profile;
  RowData brand = {...initialBrand};
  List<String> grades = [...initialGrades], subjects = [...initialSubjects];
  StreamSubscription<User?>? _authSub;
  StreamSubscription<DocumentSnapshot<RowData>>? _brandSub,
      _catalogSub,
      _profileSub;
  String? get uid => _auth?.currentUser?.uid;
  String get studentCode => uid == null
      ? ''
      : 'ST-${uid!.substring(0, min(uid!.length, 12)).toUpperCase()}';
  FirebaseFirestore get db =>
      _db ?? (throw StateError('إعداد Firebase لم يكتمل بعد'));
  bool get signedIn =>
      profile != null && uid != null && (owner || deviceVerified);

  Future<void> initialize() async {
    const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
    const appId = String.fromEnvironment('FIREBASE_APP_ID');
    const sender = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
    const project = String.fromEnvironment('FIREBASE_PROJECT_ID');
    try {
      final hasDefines = [
        apiKey,
        appId,
        sender,
        project,
      ].every((value) => value.isNotEmpty);
      if (!hasDefines && !useNativeFirebase) {
        setupError = 'نسخة معاينة: ربط مشروع Firebase متاح في تطبيق أندرويد.';
        return;
      }
      await Firebase.initializeApp(
        options: hasDefines
            ? const FirebaseOptions(
                apiKey: apiKey,
                appId: appId,
                messagingSenderId: sender,
                projectId: project,
              )
            : null,
      );
      _db = FirebaseFirestore.instance;
      _db!.settings = const Settings(persistenceEnabled: false);
      _auth = FirebaseAuth.instance;
      await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(true);
      ready = true;
      _brandSub = db
          .doc('settings/branding')
          .snapshots()
          .listen(
            (doc) {
              brand = {...initialBrand, ...?doc.data()};
              notifyListeners();
            },
            onError: (Object e) {
              setupError = 'تعذر تحميل إعدادات المنصة؛ راجع قواعد Firebase.';
              notifyListeners();
            },
          );
      _catalogSub = db.doc('settings/catalog').snapshots().listen((doc) {
        final d = doc.data() ?? {};
        grades = List<String>.from(d['grades'] ?? initialGrades);
        subjects = List<String>.from(d['subjects'] ?? initialSubjects);
        notifyListeners();
      });
      _authSub = _auth!.authStateChanges().listen((_) {
        unawaited(refreshProfile());
      });
      await refreshProfile();
      if (uid != null) {
        try {
          await verifyDeviceBinding();
        } catch (e) {
          setupError = '$e';
          await logout();
        }
      }
    } catch (e) {
      ready = false;
      setupError = 'تعذر تهيئة Firebase. راجع إعدادات المشروع والاتصال.';
    }
  }

  Future<void> refreshProfile() async {
    // A later auth event must not apply a profile belonging to the old session.
    final current = uid;
    await _profileSub?.cancel();
    _profileSub = null;
    if (current == null) {
      profile = null;
      owner = false;
      deviceVerified = false;
      notifyListeners();
      return;
    }
    try {
      final role = await db
          .doc('roles/$current')
          .get(const GetOptions(source: Source.server));
      if (uid != current) return;
      owner = role.data()?['owner'] == true;
      _profileSub = db
          .doc('users/$current')
          .snapshots()
          .listen(
            (snap) {
              if (uid != current) return;
              profile = snap.data();
              _updateDeviceVerification();
              notifyListeners();
            },
            onError: (Object e) {
              setupError = 'تعذر تحميل الحساب. أعد تسجيل الدخول.';
              notifyListeners();
            },
          );
      final doc = await db
          .doc('users/$current')
          .get(const GetOptions(source: Source.server));
      if (uid == current) {
        profile = doc.data();
        _updateDeviceVerification();
        notifyListeners();
      }
    } catch (e) {
      if (uid == current) {
        setupError = 'تعذر التحقق من صلاحيات الحساب. راجع قواعد Firebase.';
        notifyListeners();
      }
    }
  }

  void requireReady() {
    if (!ready) throw StateError(setupError ?? 'ربط Firebase مطلوب');
  }

  void requireOwner() {
    requireReady();
    if (!owner) throw StateError('هذه الوظيفة لحساب المالك فقط');
  }

  void track(String name, [Map<String, Object>? parameters]) {
    if (!ready) return;
    unawaited(
      FirebaseAnalytics.instance.logEvent(
        name: name,
        parameters: parameters,
      ),
    );
  }

  void _updateDeviceVerification() {
    if (owner) {
      deviceVerified = true;
      return;
    }
    deviceVerified = _deviceId != null && profile?['device_id'] == _deviceId;
  }

  Future<RowData> _deviceIdentity() async {
    try {
      final value = await _security.invokeMapMethod<String, dynamic>(
        'deviceIdentity',
      );
      final id = '${value?['id'] ?? ''}';
      if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(id)) {
        throw StateError('تعذر التحقق من هوية الجهاز');
      }
      return {'id': id, 'label': '${value?['label'] ?? 'Android'}'};
    } on PlatformException {
      throw StateError('تسجيل الدخول متاح من تطبيق أندرويد المعتمد فقط');
    } on MissingPluginException {
      throw StateError('تسجيل الدخول متاح من تطبيق أندرويد المعتمد فقط');
    }
  }

  Future<void> verifyDeviceBinding() async {
    requireReady();
    final current = uid;
    if (current == null) throw StateError('سجّل الدخول أولًا');
    if (owner) {
      deviceVerified = true;
      notifyListeners();
      return;
    }
    final identity = await _deviceIdentity();
    final id = text(identity, 'id');
    final userRef = db.doc('users/$current');
    await db.runTransaction((tx) async {
      final snap = await tx.get(userRef);
      final data = snap.data();
      if (data == null) throw StateError('بيانات الحساب غير مكتملة');
      final bound = text(data, 'device_id');
      if (bound.isNotEmpty && bound != id) {
        throw StateError(
          'الحساب مرتبط بجهاز آخر. تواصل مع الإدارة لفك ربط الجهاز القديم.',
        );
      }
      if (bound.isEmpty) {
        tx.update(userRef, {
          'device_id': id,
          'device_label': text(identity, 'label', 'Android'),
          'device_bound_at': FieldValue.serverTimestamp(),
        });
      }
    });
    if (uid != current) return;
    _deviceId = id;
    deviceVerified = true;
    notifyListeners();
  }

  Future<void> register(
    String name,
    String phone,
    String grade,
    String email,
    String password,
  ) async {
    requireReady();
    if (!grades.contains(grade)) throw StateError('اختر الصف الدراسي');
    final identity = await _deviceIdentity();
    final credential = await _auth!.createUserWithEmailAndPassword(
      email: email.trim().toLowerCase(),
      password: password,
    );
    final user = credential.user!;
    try {
      await db.doc('users/${user.uid}').set({
        'name': name.trim(),
        'phone': phone.trim(),
        'grade': grade,
        'email': email.trim().toLowerCase(),
        'blocked': false,
        'device_id': identity['id'],
        'device_label': identity['label'],
        'device_bound_at': FieldValue.serverTimestamp(),
        'created_at': FieldValue.serverTimestamp(),
      });
      _deviceId = text(identity, 'id');
      deviceVerified = true;
      await refreshProfile();
      unawaited(FirebaseAnalytics.instance.logSignUp(signUpMethod: 'email'));
    } catch (e) {
      await _auth!.signOut();
      rethrow;
    }
  }

  Future<void> login(String email, String password) async {
    requireReady();
    try {
      await _auth!.signInWithEmailAndPassword(
        email: email.trim().toLowerCase(),
        password: password,
      );
      await refreshProfile();
      await verifyDeviceBinding();
      unawaited(FirebaseAnalytics.instance.logLogin(loginMethod: 'email'));
    } catch (_) {
      await _auth?.signOut();
      profile = null;
      owner = false;
      deviceVerified = false;
      rethrow;
    }
  }

  Future<void> logout() async {
    await _auth?.signOut();
    profile = null;
    owner = false;
    deviceVerified = false;
    notifyListeners();
  }

  Future<void> resetPassword(String email) async {
    requireReady();
    await _auth!.sendPasswordResetEmail(email: email.trim());
  }

  Future<List<RowData>> list(
    String collection, {
    String? field,
    dynamic equalTo,
    bool published = false,
  }) async {
    Query<RowData> q = db.collection(collection);
    if (field != null) q = q.where(field, isEqualTo: equalTo);
    if (published) q = q.where('published', isEqualTo: true);
    final snap = await q
        .limit(400)
        .get(const GetOptions(source: Source.server));
    final rows = snap.docs
        .map((d) => <String, dynamic>{...d.data(), 'id': d.id})
        .toList();
    rows.sort(
      (a, b) => ((a['position'] as num?) ?? 0).compareTo(
        (b['position'] as num?) ?? 0,
      ),
    );
    return rows;
  }

  Future<List<RowData>> courses({bool admin = false}) async {
    if (admin) {
      requireOwner();
      return list('courses');
    }
    final school = await list(
      'courses',
      field: 'grade',
      equalTo: profile?['grade'],
      published: true,
    );
    final develop = await list(
      'courses',
      field: 'kind',
      equalTo: 'develop',
      published: true,
    );
    final all = {
      for (final row in [...school, ...develop]) row['id']: row,
    }.values.toList();
    all.sort(
      (a, b) => ((a['position'] as num?) ?? 0).compareTo(
        (b['position'] as num?) ?? 0,
      ),
    );
    return all;
  }

  Stream<DocumentSnapshot<RowData>> subscription(String courseId) =>
      db.doc('users/$uid/subscriptions/$courseId').snapshots();
  Future<RowData> source(String lessonId) async {
    final row = await db
        .doc('lessonSources/$lessonId')
        .get(const GetOptions(source: Source.server));
    if (!row.exists) throw StateError('مصدر الفيديو غير موجود');
    return row.data()!;
  }

  Future<RowData> startPlayback(String lessonId, String courseId) async {
    final id = db.collection('playback').doc();
    await id.set({
      'uid': uid,
      'lesson_id': lessonId,
      'course_id': courseId,
      'created_at': FieldValue.serverTimestamp(),
    });
    final saved = await id.get(const GetOptions(source: Source.server));
    unawaited(
      FirebaseAnalytics.instance.logEvent(
        name: 'lesson_start',
        parameters: {'course_id': courseId, 'lesson_id': lessonId},
      ),
    );
    return {...saved.data()!, 'id': id.id};
  }

  Future<void> saveProgress(
    String lessonId,
    String courseId,
    double position,
    bool completed,
  ) async {
    await db.doc('users/$uid/progress/$lessonId').set({
      'lesson_id': lessonId,
      'course_id': courseId,
      'seconds': position,
      'completed': completed,
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  Future<void> audit(String action, String target) async {
    await db.collection('audit').add({
      'actor': uid,
      'action': action,
      'target': target,
      'created_at': FieldValue.serverTimestamp(),
    });
  }

  Future<void> saveBrand(RowData values) async {
    requireOwner();
    await db.doc('settings/branding').set(values);
    await audit('branding', 'updated');
  }

  Future<void> saveCatalog(
    List<String> newGrades,
    List<String> newSubjects,
  ) async {
    requireOwner();
    final removedGrades = grades.where((g) => !newGrades.contains(g));
    for (final g in removedGrades) {
      if ((await db
                  .collection('users')
                  .where('grade', isEqualTo: g)
                  .limit(1)
                  .get())
              .docs
              .isNotEmpty ||
          (await db
                  .collection('courses')
                  .where('grade', isEqualTo: g)
                  .limit(1)
                  .get())
              .docs
              .isNotEmpty)
        throw StateError('الصف $g مستخدم؛ عدّل ربط الطلبة والكورسات أولًا');
    }
    for (final s in subjects.where((s) => !newSubjects.contains(s))) {
      if ((await db
              .collection('lessons')
              .where('subject', isEqualTo: s)
              .limit(1)
              .get())
          .docs
          .isNotEmpty)
        throw StateError('القسم $s مستخدم في محاضرات');
    }
    await db.doc('settings/catalog').set({
      'grades': newGrades,
      'subjects': newSubjects,
    });
    await audit('catalog', 'updated');
  }

  Future<void> saveCourse(String? id, RowData data) async {
    requireOwner();
    final ref = id == null
        ? db.collection('courses').doc()
        : db.doc('courses/$id');
    await ref.set(data);
    await audit('course', ref.id);
  }

  Future<void> saveLesson(String? id, RowData data, RowData sourceData) async {
    requireOwner();
    final ref = id == null
        ? db.collection('lessons').doc()
        : db.doc('lessons/$id');
    final batch = db.batch();
    batch.set(ref, data);
    batch.set(db.doc('lessonSources/${ref.id}'), {
      ...sourceData,
      'course_id': data['course_id'],
      'lesson_id': ref.id,
    });
    await batch.commit();
    await audit('lesson', ref.id);
  }

  Future<void> reorder(String collection, List<RowData> rows) async {
    requireOwner();
    final batch = db.batch();
    for (var i = 0; i < rows.length; i++) {
      batch.update(db.doc('$collection/${rows[i]['id']}'), {'position': i + 1});
    }
    await batch.commit();
    await audit('reorder', collection);
  }

  Future<void> remove(String collection, String id) async {
    requireOwner();
    // Archive rather than destroying existing subscriptions, attempts and history.
    await db.doc('$collection/$id').update({
      'published': false,
      'archived': true,
    });
    await audit('archive', '$collection/$id');
  }

  Future<List<RowData>> students({String search = ''}) async {
    requireOwner();
    Query<RowData> q = db.collection('users');
    if (search.contains('@')) {
      q = q.where('email', isEqualTo: search.trim().toLowerCase());
    } else if (RegExp(r'^\+?[0-9]+$').hasMatch(search)) {
      q = q.where('phone', isEqualTo: search.trim());
    }
    final snap = await q
        .limit(200)
        .get(const GetOptions(source: Source.server));
    return snap.docs
        .where((d) => d.id != uid)
        .map((d) => <String, dynamic>{...d.data(), 'id': d.id})
        .where(
          (r) =>
              search.isEmpty ||
              search.contains('@') ||
              RegExp(r'^\+?[0-9]+$').hasMatch(search) ||
              text(r, 'name').contains(search),
        )
        .toList();
  }

  Future<void> block(String student, bool value) async {
    requireOwner();
    await db.doc('users/$student').update({'blocked': value});
    await audit(value ? 'block' : 'unblock', student);
  }

  Future<void> resetDevice(String student) async {
    requireOwner();
    await db.doc('users/$student').update({
      'device_id': null,
      'device_label': null,
      'device_bound_at': null,
    });
    await audit('device_reset', student);
  }

  Future<void> renew(
    String student,
    String courseId,
    int days,
    String requestId,
  ) async {
    requireOwner();
    final sub = db.doc('users/$student/subscriptions/$courseId');
    final receipt = db.doc('renewals/$requestId');
    await db.runTransaction((tx) async {
      if ((await tx.get(receipt)).exists) return;
      final course = await tx.get(db.doc('courses/$courseId'));
      final user = await tx.get(db.doc('users/$student'));
      final old = await tx.get(sub);
      final c = course.data()!;
      if (c['kind'] == 'school' &&
          (user.data()?['grade'] != c['grade'] || days != 30))
        throw StateError('الاشتراك الدراسي لصف الطالب ومدته ٣٠ يومًا');
      final oldEnd = seconds(old.data()?['expires_at']);
      final expires =
          max(DateTime.now().millisecondsSinceEpoch ~/ 1000, oldEnd) +
          days * 86400;
      tx.set(sub, {
        'course_id': courseId,
        'expires_at': Timestamp.fromMillisecondsSinceEpoch(expires * 1000),
        'updated_at': FieldValue.serverTimestamp(),
      });
      tx.set(receipt, {
        'actor': uid,
        'student': student,
        'course_id': courseId,
        'days': days,
        'created_at': FieldValue.serverTimestamp(),
      });
    });
    await audit('renew', '$student/$courseId');
  }

  Future<void> revoke(String student, String courseId) async {
    requireOwner();
    await db.doc('users/$student/subscriptions/$courseId').delete();
    await audit('revoke', '$student/$courseId');
  }

  Future<void> saveQuiz(String? id, RowData data) async {
    requireOwner();
    final ref = id == null
        ? db.collection('quizzes').doc()
        : db.doc('quizzes/$id');
    await ref.set(data);
    await audit('quiz', ref.id);
  }

  Future<void> saveQuestion(String? id, RowData data, RowData key) async {
    requireOwner();
    if (id == null &&
        (await db
                    .collection('questions')
                    .where('quiz_id', isEqualTo: data['quiz_id'])
                    .limit(100)
                    .get())
                .docs
                .length >=
            100) {
      throw StateError('الاختبار يدعم حتى ١٠٠ سؤال');
    }
    final ref = id == null
        ? db.collection('questions').doc()
        : db.doc('questions/$id');
    final batch = db.batch();
    batch.set(ref, data);
    batch.set(db.doc('answerKeys/${ref.id}'), key);
    await batch.commit();
    await audit('question', ref.id);
  }

  Future<RowData> startAttempt(RowData quiz) async {
    final id = '${uid}_${quiz['id']}';
    final ref = db.doc('attempts/$id');
    var snap = await ref.get(const GetOptions(source: Source.server));
    if (!snap.exists) {
      await ref.set({
        'uid': uid,
        'quiz_id': quiz['id'],
        'course_id': quiz['course_id'],
        'time_minutes': quiz['time_minutes'],
        'started_at': FieldValue.serverTimestamp(),
        'submitted_at': null,
        'answers': <String, dynamic>{},
      });
      snap = await ref.get(const GetOptions(source: Source.server));
    }
    return {...snap.data()!, 'id': id};
  }

  Future<void> submitAttempt(String id, RowData answers) async {
    await db.doc('attempts/$id').update({
      'answers': answers,
      'submitted_at': FieldValue.serverTimestamp(),
    });
  }

  Future<void> gradeAttempt(String attemptId, RowData values) async {
    requireOwner();
    await db.doc('grades/$attemptId').set({
      ...values,
      'graded_at': FieldValue.serverTimestamp(),
      'actor': uid,
    });
    await audit('grade', attemptId);
  }

  Future<void> resetAttempt(String id) async {
    requireOwner();
    final batch = db.batch();
    batch.delete(db.doc('attempts/$id'));
    batch.delete(db.doc('grades/$id'));
    await batch.commit();
    await audit('reset_attempt', id);
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _brandSub?.cancel();
    _catalogSub?.cancel();
    _profileSub?.cancel();
    super.dispose();
  }
}
