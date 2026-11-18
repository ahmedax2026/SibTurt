// SPDX-FileCopyrightText: 2026 Ahmed Elwakeel
// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as image;

import 'store.dart';
import 'app.dart';
import 'quizzes.dart';

class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key, required this.store});
  final SibStore store;
  @override
  Widget build(BuildContext context) {
    if (!store.owner)
      return const Scaffold(body: Center(child: Text('غير مصرح')));
    return Scaffold(
      appBar: AppBar(title: const Text('السوبر بانل')),
      body: ListView(
        padding: const EdgeInsets.all(22),
        children: [
          Text(
            'أهلًا، ${text(store.profile ?? {}, 'name')}',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text('إدارة منصة سيبويه من حسابك'),
          const SizedBox(height: 22),
          for (final item in <(IconData, String, Widget)>[
            (
              Icons.groups_outlined,
              'الطلبة والتفعيل والتجديد',
              AdminStudents(store: store),
            ),
            (
              Icons.video_library_outlined,
              'الكورسات والفيديوهات وترتيبها',
              AdminCourses(store: store),
            ),
            (
              Icons.quiz_outlined,
              'الأسئلة والاختبارات والنتائج',
              AdminQuizzes(store: store),
            ),
            (
              Icons.palette_outlined,
              'الصور وهوية التطبيق والإعدادات',
              AdminBrand(store: store),
            ),
            (
              Icons.category_outlined,
              'الصفوف والأقسام',
              AdminCatalog(store: store),
            ),
            (
              Icons.history,
              'سجل الإدارة والمشاهدات',
              AdminHistory(store: store),
            ),
          ])
            Card(
              child: ListTile(
                contentPadding: const EdgeInsets.all(18),
                leading: Icon(item.$1, color: const Color(0xFF9C712E)),
                title: Text(item.$2),
                trailing: const Icon(Icons.chevron_left),
                onTap: () =>
                    Navigator.of(context)
                        .push(MaterialPageRoute<void>(builder: (_) => item.$3)),
              ),
            ),
        ],
      ),
    );
  }
}

class EditField {
  const EditField(
    this.key,
    this.label, {
    this.multiline = false,
    this.number = false,
    this.toggle = false,
    this.options,
  });
  final String key, label;
  final bool multiline, number, toggle;
  final Map<String, String>? options;
}

Future<void> editRecord(
  BuildContext context,
  String title,
  List<EditField> fields,
  RowData initial,
  Future<void> Function(RowData) save,
) => showDialog<void>(
  context: context,
  builder: (_) => RecordDialog(
    title: title,
    fields: fields,
    initial: initial,
    onSave: save,
  ),
);

class RecordDialog extends StatefulWidget {
  const RecordDialog({
    super.key,
    required this.title,
    required this.fields,
    required this.initial,
    required this.onSave,
  });
  final String title;
  final List<EditField> fields;
  final RowData initial;
  final Future<void> Function(RowData) onSave;
  @override
  State<RecordDialog> createState() => _RecordDialogState();
}

class _RecordDialogState extends State<RecordDialog> {
  final values = <String, dynamic>{};
  final controllers = <String, TextEditingController>{};
  bool busy = false;
  @override
  void initState() {
    super.initState();
    for (final f in widget.fields) {
      values[f.key] =
          widget.initial[f.key] ??
          (f.toggle ? true : f.options?.keys.first ?? '');
      if (!f.toggle && f.options == null)
        controllers[f.key] = TextEditingController(
          text: '${widget.initial[f.key] ?? ''}',
        );
    }
  }

  @override
  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (busy) return;
    final data = <String, dynamic>{};
    for (final f in widget.fields) {
      if (controllers[f.key] != null) {
        final v = controllers[f.key]!.text.trim();
        if (f.number) {
          final n = num.tryParse(v);
          if (n == null || !n.isFinite || n < 0) {
            message(context, 'راجع ${f.label}');
            return;
          }
          data[f.key] = n;
        } else {
          data[f.key] = v;
        }
      } else {
        data[f.key] = values[f.key];
      }
    }
    setState(() => busy = true);
    try {
      await widget.onSave(data);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) message(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 540,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final f in widget.fields)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: f.toggle
                    ? SwitchListTile(
                        title: Text(f.label),
                        value: values[f.key] == true,
                        onChanged: busy
                            ? null
                            : (v) => setState(() => values[f.key] = v),
                      )
                    : f.options != null
                    ? DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: f.options!.containsKey(values[f.key])
                            ? values[f.key]
                            : f.options!.keys.first,
                        decoration: InputDecoration(labelText: f.label),
                        items: f.options!.entries
                            .map(
                              (e) => DropdownMenuItem(
                                value: e.key,
                                child: Text(e.value),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => values[f.key] = v,
                      )
                    : TextField(
                        controller: controllers[f.key],
                        maxLines: f.multiline ? 4 : 1,
                        keyboardType: f.number ? TextInputType.number : null,
                        decoration: InputDecoration(labelText: f.label),
                      ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: const Text('إلغاء'),
      ),
      FilledButton(
        onPressed: busy ? null : save,
        child: Text(busy ? 'جارٍ الحفظ…' : 'حفظ'),
      ),
    ],
  );
}

void requireText(RowData d, String key, String label) {
  if (text(d, key).trim().isEmpty) throw StateError('$label مطلوب');
}

String validHttps(String value) {
  final u = Uri.tryParse(value);
  if (u == null ||
      u.scheme != 'https' ||
      u.host.isEmpty ||
      u.userInfo.isNotEmpty)
    throw StateError('استخدم رابط HTTPS صحيحًا');
  return value;
}

class AdminBrand extends StatefulWidget {
  const AdminBrand({super.key, required this.store});
  final SibStore store;
  @override
  State<AdminBrand> createState() => _AdminBrandState();
}

class _AdminBrandState extends State<AdminBrand> {
  late RowData values;
  final controllers = <String, TextEditingController>{};
  bool busy = false;
  @override
  void initState() {
    super.initState();
    values = {...widget.store.brand};
    for (final key in [
      'title',
      'subtitle',
      'teacher',
      'whatsapp',
      'welcome',
      'announcement',
      'gold',
      'paper',
      'welcomeImage',
      'homeImage',
    ]) {
      controllers[key] = TextEditingController(text: text(values, key));
    }
  }

  @override
  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> pick(String key) async {
    try {
      final result = await FilePicker.pickFile(type: FileType.image);
      final bytes = result == null ? null : await result.readAsBytes();
      if (bytes == null) return;
      if (bytes.length > 15 * 1024 * 1024)
        throw StateError('اختار صورة أقل من ١٥ ميجا');
      final decoded = image.decodeImage(bytes);
      if (decoded == null) throw StateError('صيغة الصورة غير مدعومة');
      final ratio = min(1.0, 900 / max(decoded.width, decoded.height));
      final scaled = image.copyResize(
        decoded,
        width: (decoded.width * ratio).round(),
        height: (decoded.height * ratio).round(),
      );
      List<int> data = image.encodeJpg(scaled, quality: 80);
      if (data.length > 140000) data = image.encodeJpg(scaled, quality: 55);
      if (data.length > 160000)
        throw StateError('الصورة كبيرة؛ اختار صورة أبسط أو أصغر');
      controllers[key]!.text = 'data:image/jpeg;base64,${base64Encode(data)}';
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) message(context, e);
    }
  }

  Future<void> save() async {
    setState(() => busy = true);
    try {
      for (final e in controllers.entries) {
        values[e.key] = e.value.text.trim();
      }
      requireText(values, 'title', 'اسم التطبيق');
      final phone = text(values, 'whatsapp');
      if (phone.isNotEmpty && !RegExp(r'^[1-9][0-9]{7,14}$').hasMatch(phone))
        throw StateError('رقم واتساب دولي بدون + أو مسافات');
      for (final key in ['gold', 'paper']) {
        if (!RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(text(values, key)))
          throw StateError('اللون بصيغة #C6A15B');
      }
      for (final key in ['welcomeImage', 'homeImage']) {
        final value = text(values, key);
        if (value.isNotEmpty && !value.startsWith('data:image/jpeg;base64,'))
          validHttps(value);
      }
      await widget.store.saveBrand(values);
      if (mounted) message(context, 'تم تحديث شكل التطبيق');
    } catch (e) {
      if (mounted) message(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('هوية التطبيق والإعدادات')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        for (final key in ['welcomeImage', 'homeImage'])
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    key == 'welcomeImage' ? 'صورة البداية' : 'صورة الرئيسية',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 15),
                  SibImage(
                    controllers[key]!.text,
                    height: 180,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: busy ? null : () => pick(key),
                    icon: const Icon(Icons.upload_file),
                    label: const Text('اختيار صورة من الهاتف'),
                  ),
                  TextField(
                    controller: controllers[key],
                    maxLines: 1,
                    decoration: const InputDecoration(
                      labelText: 'رابط صورة HTTPS أو الصورة المختارة',
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() => controllers[key]!.clear()),
                    child: const Text('استعادة الصورة الأصلية'),
                  ),
                ],
              ),
            ),
          ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text(
            'الصور داخل التطبيق تتغير بعد الحفظ. أيقونة شاشة الهاتف تحتاج بناء إصدار جديد.',
            style: TextStyle(fontSize: 12, color: Colors.brown),
          ),
        ),
        for (final f in const [
          EditField('title', 'اسم التطبيق'),
          EditField('subtitle', 'الوصف تحت الاسم'),
          EditField('teacher', 'اسم المدرس'),
          EditField('whatsapp', 'رقم واتساب دولي، بدون +'),
          EditField('welcome', 'رسالة البداية', multiline: true),
          EditField('announcement', 'إعلان الرئيسية', multiline: true),
          EditField('gold', 'اللون الأساسي، مثل #C6A15B'),
          EditField('paper', 'لون الخلفية، مثل #FAF7F0'),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: TextField(
              controller: controllers[f.key],
              maxLines: f.multiline ? 3 : 1,
              decoration: InputDecoration(labelText: f.label),
            ),
          ),
        for (final entry in const {
          'requireHeadphones': 'اشتراط توصيل سماعة',
          'blockVpn': 'إيقاف المشاهدة عند كشف VPN',
          'blockProxy': 'إيقاف المشاهدة عند كشف بروكسي',
        }.entries)
          SwitchListTile(
            title: Text(entry.value),
            value: values[entry.key] != false,
            onChanged: (v) => setState(() => values[entry.key] = v),
          ),
        FilledButton(
          onPressed: busy ? null : save,
          child: Text(busy ? 'جارٍ الحفظ…' : 'حفظ التغييرات'),
        ),
      ],
    ),
  );
}

class AdminCatalog extends StatefulWidget {
  const AdminCatalog({super.key, required this.store});
  final SibStore store;
  @override
  State<AdminCatalog> createState() => _AdminCatalogState();
}

class _AdminCatalogState extends State<AdminCatalog> {
  late TextEditingController grades, subjects;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    grades = TextEditingController(text: widget.store.grades.join('\n'));
    subjects = TextEditingController(text: widget.store.subjects.join('\n'));
  }

  @override
  void dispose() {
    grades.dispose();
    subjects.dispose();
    super.dispose();
  }

  Future<void> save() async {
    final g = grades.text
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final s = subjects.text
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (g.isEmpty ||
        s.isEmpty ||
        g.toSet().length != g.length ||
        s.toSet().length != s.length) {
      message(context, 'اكتب أسماء غير مكررة، كل اسم في سطر');
      return;
    }
    setState(() => busy = true);
    try {
      await widget.store.saveCatalog(g, s);
      if (mounted) message(context, 'تم حفظ الأقسام وترتيبها');
    } catch (e) {
      if (mounted) message(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('الصفوف والأقسام')),
    body: ListView(
      padding: const EdgeInsets.all(22),
      children: [
        const Text('كل اسم في سطر. ترتيب السطور هو ترتيب العرض.'),
        const SizedBox(height: 18),
        TextField(
          controller: grades,
          minLines: 3,
          maxLines: 10,
          decoration: const InputDecoration(labelText: 'الصفوف الدراسية'),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: subjects,
          minLines: 6,
          maxLines: 15,
          decoration: const InputDecoration(labelText: 'الأقسام'),
        ),
        const SizedBox(height: 15),
        const Text(
          'أسماء مستخدمة في حسابات أو دروس لا تُحذف من هنا؛ عدّل ربط المحتوى والطلبة أولًا.',
          style: TextStyle(color: Colors.brown, fontSize: 12),
        ),
        const SizedBox(height: 20),
        FilledButton(onPressed: busy ? null : save, child: const Text('حفظ')),
      ],
    ),
  );
}

class AdminStudents extends StatefulWidget {
  const AdminStudents({super.key, required this.store});
  final SibStore store;
  @override
  State<AdminStudents> createState() => _AdminStudentsState();
}

class _AdminStudentsState extends State<AdminStudents> {
  late Future<List<RowData>> rows;
  final search = TextEditingController();
  @override
  void initState() {
    super.initState();
    reload();
  }

  void reload() {
    rows = widget.store.students(search: search.text.trim());
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('الطلبة والاشتراكات')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: search,
            decoration: InputDecoration(
              labelText: 'بحث بالاسم أو الإيميل أو الهاتف',
              suffixIcon: IconButton(
                onPressed: () => setState(reload),
                icon: const Icon(Icons.search),
              ),
            ),
            onSubmitted: (_) => setState(reload),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<RowData>>(
            future: rows,
            builder: (context, snap) {
              if (snap.hasError)
                return const Center(child: Text('تعذر تحميل الطلبة'));
              if (!snap.hasData)
                return const Center(child: CircularProgressIndicator());
              return ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  const Text(
                    'تُعرض حتى ٢٠٠ نتيجة. استخدم الإيميل أو الهاتف للوصول لطالب محدد.',
                    style: TextStyle(fontSize: 11),
                  ),
                  for (final user in snap.data!)
                    Card(
                      child: ListTile(
                        leading: Icon(
                          user['blocked'] == true
                              ? Icons.lock
                              : Icons.person_outline,
                        ),
                        title: Text(text(user, 'name')),
                        subtitle: Text(
                          '${text(user, 'email')}\n${text(user, 'grade')}',
                        ),
                        isThreeLine: true,
                        trailing: const Icon(Icons.chevron_left),
                        onTap: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => AdminStudentDetail(
                                store: widget.store,
                                user: user,
                              ),
                            ),
                          );
                          if (mounted) setState(reload);
                        },
                      ),
                    ),
                  if (snap.data!.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(40),
                      child: Text('لا يوجد طلبة مطابقون'),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    ),
  );
}

class AdminStudentDetail extends StatefulWidget {
  const AdminStudentDetail({
    super.key,
    required this.store,
    required this.user,
  });
  final SibStore store;
  final RowData user;
  @override
  State<AdminStudentDetail> createState() => _AdminStudentDetailState();
}

class _AdminStudentDetailState extends State<AdminStudentDetail> {
  late RowData user;
  late Future<List<RowData>> rows;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    user = {...widget.user};
    rows = widget.store.courses(admin: true);
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
      if (mounted) message(context, 'تم تنفيذ الإجراء');
    } catch (e) {
      if (mounted) message(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> renew(RowData c) async {
    final days = TextEditingController(text: '30');
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تفعيل بعد تأكيد الدفع'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text(c, 'title')),
            const SizedBox(height: 16),
            if (c['kind'] == 'develop')
              TextField(
                controller: days,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'عدد الأيام'),
              )
            else
              const Text('٣٠ يومًا — تُضاف على المدة المتبقية'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, int.tryParse(days.text)),
            child: const Text('تم الدفع — فعّل'),
          ),
        ],
      ),
    );
    days.dispose();
    if (result == null) return;
    if (result < 1 || result > 365) {
      if (mounted) message(context, 'المدة من يوم إلى ٣٦٥ يومًا');
      return;
    }
    final request = widget.store.db.collection('renewals').doc().id;
    await run(() => widget.store.renew(user['id'], c['id'], result, request));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(text(user, 'name'))),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text(user, 'email')),
                Text(text(user, 'phone')),
                Text(text(user, 'grade')),
                const SizedBox(height: 8),
                Text(
                  text(user, 'device_id').isEmpty
                      ? 'الجهاز: غير مرتبط'
                      : 'الجهاز: ${text(user, 'device_label', 'Android')}',
                ),
                if (text(user, 'device_id').isNotEmpty)
                  Text(
                    'تاريخ الربط: ${dateLabel(user['device_bound_at'])}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                SelectableText(user['id']),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => editRecord(
                    context,
                    'بيانات الطالب',
                    [
                      const EditField('name', 'الاسم'),
                      const EditField('phone', 'الهاتف'),
                      EditField(
                        'grade',
                        'الصف',
                        options: {for (final g in widget.store.grades) g: g},
                      ),
                    ],
                    user,
                    (d) async {
                      await widget.store.db
                          .doc('users/${user['id']}')
                          .update(d);
                      setState(() => user.addAll(d));
                      await widget.store.audit('student_edit', user['id']);
                    },
                  ),
                  child: const Text('تعديل بيانات الطالب'),
                ),
                OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => run(
                          () => widget.store.resetPassword(text(user, 'email')),
                        ),
                  child: const Text('إرسال استعادة كلمة المرور'),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.phonelink_erase),
                  onPressed: busy || text(user, 'device_id').isEmpty
                      ? null
                      : () async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('فك ربط الجهاز؟'),
                              content: const Text(
                                'سيُمنع الجهاز الحالي، وسيُربط الحساب بأول جهاز يسجل الدخول بعد ذلك.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('إلغاء'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('فك الربط'),
                                ),
                              ],
                            ),
                          );
                          if (confirmed != true) return;
                          await run(() async {
                            await widget.store.resetDevice(user['id']);
                            setState(() {
                              user['device_id'] = null;
                              user['device_label'] = null;
                              user['device_bound_at'] = null;
                            });
                          });
                        },
                  label: const Text('فك ربط الجهاز'),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () => run(() async {
                          await widget.store.block(
                            user['id'],
                            user['blocked'] != true,
                          );
                          setState(
                            () => user['blocked'] = user['blocked'] != true,
                          );
                        }),
                  child: Text(
                    user['blocked'] == true
                        ? 'إلغاء إيقاف الحساب'
                        : 'إيقاف الحساب',
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text('الاشتراكات', style: Theme.of(context).textTheme.headlineSmall),
        FutureBuilder<List<RowData>>(
          future: rows,
          builder: (context, snap) {
            if (!snap.hasData)
              return const Center(child: CircularProgressIndicator());
            return Column(
              children: [
                for (final c in snap.data!.where(
                  (c) => c['kind'] == 'develop' || c['grade'] == user['grade'],
                ))
                  StreamBuilder<DocumentSnapshot<RowData>>(
                    stream: widget.store.db
                        .doc('users/${user['id']}/subscriptions/${c['id']}')
                        .snapshots(),
                    builder: (context, sub) => Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              text(c, 'title'),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'ينتهي: ${dateLabel(sub.data?.data()?['expires_at'])}',
                            ),
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: busy ? null : () => renew(c),
                              child: const Text('تفعيل / تجديد'),
                            ),
                            if (sub.data?.exists == true)
                              TextButton(
                                onPressed: busy
                                    ? null
                                    : () => run(
                                        () => widget.store.revoke(
                                          user['id'],
                                          c['id'],
                                        ),
                                      ),
                                child: const Text(
                                  'إلغاء الاشتراك',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    ),
  );
}

class AdminCourses extends StatefulWidget {
  const AdminCourses({super.key, required this.store});
  final SibStore store;
  @override
  State<AdminCourses> createState() => _AdminCoursesState();
}

class _AdminCoursesState extends State<AdminCourses> {
  late Future<List<RowData>> rows;
  @override
  void initState() {
    super.initState();
    reload();
  }

  void reload() {
    rows = widget.store.courses(admin: true);
  }

  Future<void> edit([RowData? c]) async {
    await editRecord(
      context,
      c == null ? 'إضافة كورس' : 'تعديل الكورس',
      [
        const EditField('title', 'اسم الكورس'),
        const EditField(
          'kind',
          'نوع الاشتراك',
          options: {
            'school': 'دراسي — ٣٠ يومًا',
            'develop': 'طور نفسك — مستقل',
          },
        ),
        EditField(
          'grade',
          'الصف',
          options: {for (final g in widget.store.grades) g: g},
        ),
        const EditField('description', 'الوصف', multiline: true),
        const EditField('position', 'الترتيب', number: true),
        const EditField('published', 'منشور للطلبة', toggle: true),
      ],
      c ??
          {
            'position': 1,
            'kind': 'school',
            'grade': widget.store.grades.first,
            'published': true,
          },
      (d) async {
        requireText(d, 'title', 'اسم الكورس');
        if (d['kind'] == 'school') {
          final others = await widget.store.courses(admin: true);
          if (others.any(
            (x) =>
                x['kind'] == 'school' &&
                x['grade'] == d['grade'] &&
                x['id'] != c?['id'] &&
                x['archived'] != true,
          ))
            throw StateError('يوجد كورس دراسي لهذا الصف يضم كل الأقسام');
        }
        await widget.store.saveCourse(c?['id'], d);
      },
    );
    if (mounted) setState(reload);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('الكورسات والفيديوهات'),
      actions: [IconButton(onPressed: edit, icon: const Icon(Icons.add))],
    ),
    body: FutureBuilder<List<RowData>>(
      future: rows,
      builder: (context, snap) {
        if (snap.hasError)
          return const Center(child: Text('تعذر تحميل المحتوى'));
        if (!snap.hasData)
          return const Center(child: CircularProgressIndicator());
        final items = snap.data!;
        return ReorderableListView(
          padding: const EdgeInsets.all(18),
          header: const Padding(
            padding: EdgeInsets.only(bottom: 20),
            child: Text('اسحب الكورس لتغيير الترتيب. افتحه لإدارة محاضراته.'),
          ),
          onReorder: (old, newIndex) async {
            if (newIndex > old) newIndex--;
            final row = items.removeAt(old);
            items.insert(newIndex, row);
            try {
              await widget.store.reorder('courses', items);
              if (mounted) setState(reload);
            } catch (e) {
              if (context.mounted) message(context, e);
            }
          },
          children: [
            for (final c in items)
              Card(
                key: ValueKey(c['id']),
                child: ListTile(
                  title: Text(text(c, 'title')),
                  subtitle: Text(
                    '${c['kind'] == 'develop' ? 'طور نفسك' : text(c, 'grade')} • ${c['published'] == true ? 'منشور' : 'مخفي'}',
                  ),
                  leading: const Icon(Icons.drag_indicator),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          AdminLessons(store: widget.store, course: c),
                    ),
                  ),
                  trailing: IconButton(
                    onPressed: () => edit(c),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}

class AdminLessons extends StatefulWidget {
  const AdminLessons({super.key, required this.store, required this.course});
  final SibStore store;
  final RowData course;
  @override
  State<AdminLessons> createState() => _AdminLessonsState();
}

class _AdminLessonsState extends State<AdminLessons> {
  late Future<List<RowData>> rows;
  @override
  void initState() {
    super.initState();
    reload();
  }

  void reload() {
    rows = widget.store.list(
      'lessons',
      field: 'course_id',
      equalTo: widget.course['id'],
    );
  }

  Future<void> edit([RowData? lesson]) async {
    RowData source = {};
    if (lesson != null) {
      source =
          (await widget.store.db.doc('lessonSources/${lesson['id']}').get())
              .data() ??
          {};
    }
    if (!mounted) return;
    await editRecord(
      context,
      lesson == null ? 'إضافة محاضرة' : 'تعديل المحاضرة',
      [
        const EditField('title', 'عنوان المحاضرة'),
        EditField(
          'subject',
          'القسم',
          options: {
            for (final s in [...widget.store.subjects, 'طور نفسك']) s: s,
          },
        ),
        const EditField(
          'provider',
          'مصدر الفيديو',
          options: {
            'youtube': 'YouTube',
            'drive': 'Google Drive',
            'mp4': 'MP4 مباشر',
            'hls': 'HLS مباشر',
            'cloudflare': 'Cloudflare — رابط تشغيل HTTPS',
          },
        ),
        const EditField('url', 'رابط الفيديو'),
        const EditField('attachment', 'رابط الملزمة PDF (اختياري)'),
        const EditField('notes', 'شرح وملاحظات', multiline: true),
        const EditField('position', 'ترتيب المحاضرة', number: true),
        const EditField('published', 'منشورة للطلبة', toggle: true),
      ],
      {
        ...?(lesson),
        ...source,
        'subject': lesson?['subject'] ?? widget.store.subjects.first,
        'provider': source['provider'] ?? 'youtube',
        'position': lesson?['position'] ?? 1,
        'published': lesson?['published'] ?? true,
      },
      (d) async {
        requireText(d, 'title', 'العنوان');
        validHttps(text(d, 'url'));
        if (text(d, 'attachment').isNotEmpty) validHttps(text(d, 'attachment'));
        final provider = text(d, 'provider');
        final u = Uri.parse(text(d, 'url'));
        if (provider == 'youtube' &&
            ![
              'youtube.com',
              'www.youtube.com',
              'm.youtube.com',
              'youtu.be',
              'music.youtube.com',
            ].contains(u.host))
          throw StateError('استخدم رابط فيديو YouTube صحيحًا');
        if (provider == 'drive' && u.host != 'drive.google.com')
          throw StateError('استخدم رابط Google Drive');
        final metadata = {
          'course_id': widget.course['id'],
          'title': d['title'],
          'subject': d['subject'],
          'notes': d['notes'],
          'position': d['position'],
          'published': d['published'],
        };
        await widget.store.saveLesson(lesson?['id'], metadata, {
          'provider': provider,
          'url': d['url'],
          'attachment': d['attachment'],
        });
      },
    );
    if (mounted) setState(reload);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(text(widget.course, 'title')),
      actions: [IconButton(onPressed: edit, icon: const Icon(Icons.add))],
    ),
    body: FutureBuilder<List<RowData>>(
      future: rows,
      builder: (context, snap) {
        if (!snap.hasData)
          return const Center(child: CircularProgressIndicator());
        final items = snap.data!;
        return ReorderableListView(
          padding: const EdgeInsets.all(18),
          header: const Padding(
            padding: EdgeInsets.only(bottom: 18),
            child: Text(
              'اسحب المحاضرة لترتيبها. الإخفاء يمنع وصول الطلبة ويحافظ على سجلهم.',
            ),
          ),
          onReorder: (old, next) async {
            if (next > old) next--;
            items.insert(next, items.removeAt(old));
            try {
              await widget.store.reorder('lessons', items);
              if (mounted) setState(reload);
            } catch (e) {
              if (context.mounted) message(context, e);
            }
          },
          children: [
            for (final l in items)
              Card(
                key: ValueKey(l['id']),
                child: ListTile(
                  leading: const Icon(Icons.drag_indicator),
                  title: Text(text(l, 'title')),
                  subtitle: Text(
                    '${text(l, 'subject')} • ${l['published'] == true ? 'منشورة' : 'مخفية'}',
                  ),
                  onTap: () => edit(l),
                  trailing: Wrap(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'اختبارات المحاضرة',
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => AdminQuizzes(
                              store: widget.store,
                              lesson: l,
                            ),
                          ),
                        ),
                        icon: const Icon(Icons.quiz_outlined),
                      ),
                      IconButton(
                        tooltip: l['published'] == true
                            ? 'إخفاء'
                            : 'إعادة النشر',
                        onPressed: () async {
                          try {
                            await widget.store.db
                                .doc('lessons/${l['id']}')
                                .update({
                                  'published': l['published'] != true,
                                });
                            await widget.store.audit(
                              'lesson_visibility',
                              l['id'],
                            );
                            if (mounted) setState(reload);
                          } catch (e) {
                            if (context.mounted) message(context, e);
                          }
                        },
                        icon: Icon(
                          l['published'] == true
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}

class AdminHistory extends StatelessWidget {
  const AdminHistory({super.key, required this.store});
  final SibStore store;
  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('سجل المنصة'),
        bottom: const TabBar(
          tabs: [
            Tab(text: 'الإدارة'),
            Tab(text: 'جلسات المشاهدة'),
          ],
        ),
      ),
      body: TabBarView(
        children: [
          for (final collection in ['audit', 'playback'])
            FutureBuilder<List<RowData>>(
              future: store.list(collection),
              builder: (context, snap) {
                if (snap.hasError)
                  return const Center(child: Text('تعذر التحميل'));
                if (!snap.hasData)
                  return const Center(child: CircularProgressIndicator());
                final rows = [...snap.data!]
                  ..sort(
                    (a, b) =>
                        seconds(b['created_at'])
                            .compareTo(seconds(a['created_at'])),
                  );
                return ListView(
                  padding: const EdgeInsets.all(18),
                  children: [
                    for (final r in rows)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                text(
                                  r,
                                  collection == 'audit'
                                      ? 'action'
                                      : 'lesson_id',
                                ),
                              ),
                              SelectableText(
                                text(
                                  r,
                                  collection == 'audit' ? 'target' : 'id',
                                ),
                              ),
                              SelectableText(
                                text(
                                  r,
                                  collection == 'audit' ? 'actor' : 'uid',
                                ),
                              ),
                              Text(
                                dateLabel(r['created_at']),
                                style: const TextStyle(fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    ),
  );
}
