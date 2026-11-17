// SPDX-FileCopyrightText: 2026 Ahmed Elwakeel
// SPDX-License-Identifier: Apache-2.0
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'store.dart';
import 'app.dart';
import 'admin.dart';

class StudentQuizzes extends StatefulWidget {
  const StudentQuizzes({super.key, required this.store});
  final SibStore store;
  @override
  State<StudentQuizzes> createState() => _StudentQuizzesState();
}

class _StudentQuizzesState extends State<StudentQuizzes> {
  late Future<List<RowData>> rows;
  @override
  void initState() {
    super.initState();
    rows = load();
  }

  Future<List<RowData>> load() async {
    final result = <RowData>[];
    for (final c in await widget.store.courses()) {
      result.addAll(
        await widget.store.list(
          'quizzes',
          field: 'course_id',
          equalTo: c['id'],
          published: true,
        ),
      );
    }
    return result;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<RowData>>(
    future: rows,
    builder: (context, snap) {
      if (snap.hasError)
        return const Center(child: Text('تعذر تحميل الاختبارات'));
      if (!snap.hasData)
        return const Center(child: CircularProgressIndicator());
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'اختباراتي وواجباتي',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 15),
          if (snap.data!.isEmpty)
            const Padding(
              padding: EdgeInsets.all(30),
              child: Text('لا توجد اختبارات منشورة بعد.'),
            ),
          for (final quiz in snap.data!)
            Card(
              child: ListTile(
                contentPadding: const EdgeInsets.all(18),
                leading: const Icon(Icons.assignment_outlined),
                title: Text(text(quiz, 'title')),
                subtitle: Text(
                  '${quiz['kind'] == 'homework' ? 'واجب' : 'اختبار'} • ${quiz['time_minutes'] == 0 ? 'بدون توقيت' : '${quiz['time_minutes']} دقيقة'}',
                ),
                trailing: const Icon(Icons.chevron_left),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => TakeQuiz(store: widget.store, quiz: quiz),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}

class TakeQuiz extends StatefulWidget {
  const TakeQuiz({super.key, required this.store, required this.quiz});
  final SibStore store;
  final RowData quiz;
  @override
  State<TakeQuiz> createState() => _TakeQuizState();
}

class _TakeQuizState extends State<TakeQuiz> {
  RowData? attempt;
  List<RowData>? questions;
  RowData answers = {};
  String? failure;
  bool busy = false;
  int remaining = 0;
  Timer? timer;
  final elapsed = Stopwatch();
  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  Future<void> load() async {
    try {
      final a = await widget.store.startAttempt(widget.quiz);
      final q = await widget.store.list(
        'questions',
        field: 'quiz_id',
        equalTo: widget.quiz['id'],
      );
      if (!mounted) return;
      setState(() {
        attempt = a;
        questions = q;
        answers = Map<String, dynamic>.from(a['answers'] ?? {});
      });
      final minutes = (a['time_minutes'] as num?)?.toInt() ?? 0;
      if (minutes > 0 && a['submitted_at'] == null) {
        elapsed.start();
        final initialRemaining =
            (minutes * 60 -
                    (DateTime.now().millisecondsSinceEpoch ~/ 1000 -
                        seconds(a['started_at'])))
                .clamp(0, minutes * 60);
        remaining = initialRemaining;
        timer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (!mounted) return;
          setState(
            () => remaining = initialRemaining - elapsed.elapsed.inSeconds,
          );
          if (remaining <= 0) {
            timer?.cancel();
            unawaited(submit());
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => failure = e.toString());
    }
  }

  Future<void> submit() async {
    if (busy || attempt == null) return;
    setState(() => busy = true);
    try {
      await widget.store.submitAttempt(attempt!['id'], answers);
      timer?.cancel();
      final saved = await widget.store.db
          .doc('attempts/${attempt!['id']}')
          .get(const GetOptions(source: Source.server));
      if (mounted)
        setState(() => attempt = {...saved.data()!, 'id': attempt!['id']});
    } catch (e) {
      if (mounted) message(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    elapsed.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(text(widget.quiz, 'title'))),
    body: failure != null
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'تعذر فتح الاختبار؛ تأكد من تفعيل الاشتراك.\n$failure',
              ),
            ),
          )
        : questions == null
        ? const Center(child: CircularProgressIndicator())
        : attempt?['submitted_at'] != null
        ? QuizResult(store: widget.store, attempt: attempt!, quiz: widget.quiz)
        : ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(text(widget.quiz, 'description')),
              if ((widget.quiz['time_minutes'] as num? ?? 0) > 0)
                Chip(
                  label: Text(
                    'المتبقي: ${remaining ~/ 60}:${(remaining % 60).clamp(0, 59).toString().padLeft(2, '0')}',
                  ),
                ),
              const Text(
                'محاولة واحدة. الإجابات لا تُحفظ قبل التسليم.',
                style: TextStyle(fontSize: 12, color: Colors.brown),
              ),
              for (final q in questions!)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          text(q, 'prompt'),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${q['points']} درجة',
                          style: const TextStyle(fontSize: 11),
                        ),
                        if (q['type'] == 'mcq')
                          for (
                            var i = 0;
                            i < (q['choices'] as List).length;
                            i++
                          )
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text('${q['choices'][i]}'),
                              value: answers[q['id']] == i,
                              onChanged: busy
                                  ? null
                                  : (_) => setState(() => answers[q['id']] = i),
                            )
                        else
                          TextField(
                            maxLines: 5,
                            onChanged: (v) => answers[q['id']] = v,
                            decoration: const InputDecoration(
                              labelText: 'إجابتك',
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: busy ? null : submit,
                child: Text(busy ? 'جارٍ التسليم…' : 'تسليم الإجابات'),
              ),
            ],
          ),
  );
}

class QuizResult extends StatelessWidget {
  const QuizResult({
    super.key,
    required this.store,
    required this.attempt,
    required this.quiz,
  });
  final SibStore store;
  final RowData attempt, quiz;
  @override
  Widget build(BuildContext context) {
    if (quiz['show_results'] != true)
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(35),
          child: Text('تم تسليم إجاباتك. الإدارة ستحدد موعد ظهور النتيجة.'),
        ),
      );
    return FutureBuilder<DocumentSnapshot<RowData>>(
      future: store.db
          .doc('grades/${attempt['id']}')
          .get(const GetOptions(source: Source.server)),
      builder: (context, snap) {
        if (snap.hasError || snap.hasData && !snap.data!.exists)
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(35),
              child: Text('تم التسليم — في انتظار التصحيح.'),
            ),
          );
        if (!snap.hasData)
          return const Center(child: CircularProgressIndicator());
        final grade = snap.data!.data()!;
        return ListView(
          padding: const EdgeInsets.all(25),
          children: [
            const Icon(Icons.task_alt, size: 70, color: Color(0xFF9C712E)),
            const SizedBox(height: 20),
            Text(
              '${grade['score']} / ${grade['total']}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 20),
            Text(text(grade, 'feedback'), style: const TextStyle(height: 1.8)),
            for (final item in List<RowData>.from(grade['items'] ?? []))
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        text(item, 'prompt'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text('إجابتك: ${item['answer']}'),
                      Text('النموذج: ${item['model']}'),
                      Text('الدرجة: ${item['score']} / ${item['points']}'),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class AdminQuizzes extends StatefulWidget {
  const AdminQuizzes({super.key, required this.store});
  final SibStore store;
  @override
  State<AdminQuizzes> createState() => _AdminQuizzesState();
}

class _AdminQuizzesState extends State<AdminQuizzes> {
  late Future<List<RowData>> rows;
  @override
  void initState() {
    super.initState();
    reload();
  }

  void reload() {
    rows = widget.store.list('quizzes');
  }

  Future<void> edit([RowData? quiz]) async {
    final courses = await widget.store.courses(admin: true);
    if (!mounted) return;
    if (courses.isEmpty) {
      message(context, 'أضف كورسًا أولًا');
      return;
    }
    await editRecord(
      context,
      quiz == null ? 'إضافة اختبار / واجب' : 'تعديل الاختبار',
      [
        const EditField('title', 'العنوان'),
        EditField(
          'course_id',
          'الكورس',
          options: {for (final c in courses) c['id']: text(c, 'title')},
        ),
        const EditField(
          'kind',
          'النوع',
          options: {'quiz': 'اختبار', 'homework': 'واجب'},
        ),
        const EditField('description', 'التعليمات', multiline: true),
        const EditField(
          'time_minutes',
          'الدقائق، صفر بدون توقيت',
          number: true,
        ),
        const EditField('position', 'الترتيب', number: true),
        const EditField('published', 'منشور للطلبة', toggle: true),
        const EditField(
          'show_results',
          'عرض النتائج المصححة للطلبة',
          toggle: true,
        ),
      ],
      quiz ??
          {
            'course_id': courses.first['id'],
            'kind': 'quiz',
            'time_minutes': 0,
            'position': 1,
            'published': false,
            'show_results': false,
          },
      (d) async {
        requireText(d, 'title', 'العنوان');
        if ((d['time_minutes'] as num) > 180 || d['time_minutes'] != (d['time_minutes'] as num).round())
          throw StateError('مدة الاختبار حتى ١٨٠ دقيقة');
        await widget.store.saveQuiz(quiz?['id'], d);
      },
    );
    if (mounted) setState(reload);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('الاختبارات والواجبات'),
      actions: [IconButton(onPressed: edit, icon: const Icon(Icons.add))],
    ),
    body: FutureBuilder<List<RowData>>(
      future: rows,
      builder: (context, snap) {
        if (!snap.hasData)
          return const Center(child: CircularProgressIndicator());
        return ListView(
          padding: const EdgeInsets.all(18),
          children: [
            for (final q in snap.data!)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        text(q, 'title'),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(q['published'] == true ? 'منشور' : 'مخفي'),
                      Wrap(
                        spacing: 8,
                        children: [
                          TextButton(
                            onPressed: () => edit(q),
                            child: const Text('الإعدادات'),
                          ),
                          TextButton(
                            onPressed: () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => AdminQuestions(
                                    store: widget.store,
                                    quiz: q,
                                  ),
                                ),
                              );
                              if (mounted) setState(reload);
                            },
                            child: const Text('الأسئلة وترتيبها'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => AdminQuizResults(
                                  store: widget.store,
                                  quiz: q,
                                ),
                              ),
                            ),
                            child: const Text('التصحيح والنتائج'),
                          ),
                        ],
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

class AdminQuestions extends StatefulWidget {
  const AdminQuestions({super.key, required this.store, required this.quiz});
  final SibStore store;
  final RowData quiz;
  @override
  State<AdminQuestions> createState() => _AdminQuestionsState();
}

class _AdminQuestionsState extends State<AdminQuestions> {
  late Future<List<RowData>> rows;
  late bool published;
  @override
  void initState() {
    super.initState();
    published = widget.quiz['published'] == true;
    reload();
  }

  void reload() {
    rows = widget.store.list(
      'questions',
      field: 'quiz_id',
      equalTo: widget.quiz['id'],
    );
  }

  Future<void> edit([RowData? question]) async {
    final key = question == null
        ? <String, dynamic>{}
        : (await widget.store.db.doc('answerKeys/${question['id']}').get())
                  .data() ??
              {};
    if (!mounted) return;
    await editRecord(
      context,
      question == null ? 'إضافة سؤال' : 'تعديل السؤال',
      const [
        EditField('prompt', 'نص السؤال', multiline: true),
        EditField(
          'type',
          'نوع السؤال',
          options: {'mcq': 'اختيار من متعدد', 'essay': 'مقالي'},
        ),
        EditField('choices', 'الاختيارات، كل اختيار في سطر', multiline: true),
        EditField(
          'correct_index',
          'رقم الاختيار الصحيح، يبدأ من ١',
          number: true,
        ),
        EditField('model_answer', 'الإجابة النموذجية للمقالي', multiline: true),
        EditField('points', 'درجة السؤال', number: true),
        EditField('position', 'ترتيب السؤال', number: true),
      ],
      {
        ...?(question),
        ...key,
        'choices': (question?['choices'] as List? ?? []).join('\n'),
        'type': question?['type'] ?? 'mcq',
        'correct_index': ((key['correct_index'] as num?) ?? 0) + 1,
        'points': question?['points'] ?? 1,
        'position': question?['position'] ?? 1,
      },
      (d) async {
        requireText(d, 'prompt', 'نص السؤال');
        final choices = text(
          d,
          'choices',
        ).split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
        final correct = (d['correct_index'] as num).toInt() - 1;
        final points = d['points'] as num;
        if (points <= 0 || points > 100)
          throw StateError('الدرجة من ١ إلى ١٠٠');
        if (d['type'] == 'mcq' &&
            (choices.length < 2 ||
                choices.length > 6 ||
                correct < 0 ||
                correct >= choices.length))
          throw StateError('اكتب من اختيارين إلى ٦ اختيارات وحدد الصحيح');
        await widget.store.saveQuestion(
          question?['id'],
          {
            'quiz_id': widget.quiz['id'],
            'course_id': widget.quiz['course_id'],
            'prompt': d['prompt'],
            'type': d['type'],
            'choices': choices,
            'points': points,
            'position': d['position'],
          },
          {'correct_index': correct, 'model_answer': d['model_answer']},
        );
      },
    );
    if (mounted) setState(reload);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('بنك الأسئلة'),
      actions: [
        IconButton(
          onPressed: published ? null : edit,
          icon: const Icon(Icons.add),
        ),
      ],
    ),
    body: FutureBuilder<List<RowData>>(
      future: rows,
      builder: (context, snap) {
        if (!snap.hasData)
          return const Center(child: CircularProgressIndicator());
        final items = snap.data!;
        return ReorderableListView(
          padding: const EdgeInsets.all(18),
          header: Column(
            children: [
              SwitchListTile(
                title: const Text('منشور للطلبة'),
                subtitle: const Text(
                  'أخفِ الاختبار لتعديل الأسئلة. لا تعدّل أثناء حل الطلبة.',
                ),
                value: published,
                onChanged: (v) async {
                  try {
                    await widget.store.db
                        .doc('quizzes/${widget.quiz['id']}')
                        .update({'published': v});
                    setState(() => published = v);
                  } catch (e) {
                    if (context.mounted) message(context, e);
                  }
                },
              ),
              const SizedBox(height: 15),
            ],
          ),
          onReorder: (old, next) async {
            if (published) return;
            if (next > old) next--;
            items.insert(next, items.removeAt(old));
            try {
              await widget.store.reorder('questions', items);
              if (mounted) setState(reload);
            } catch (e) {
              if (context.mounted) message(context, e);
            }
          },
          children: [
            for (final q in items)
              Card(
                key: ValueKey(q['id']),
                child: ListTile(
                  title: Text(text(q, 'prompt')),
                  subtitle: Text(
                    '${q['points']} درجة • ${q['type'] == 'mcq' ? 'اختيار' : 'مقالي'}',
                  ),
                  leading: const Icon(Icons.drag_indicator),
                  onTap: published ? null : () => edit(q),
                  trailing: IconButton(
                    tooltip: 'حذف السؤال',
                    onPressed: published
                        ? null
                        : () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('حذف السؤال؟'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('إلغاء'),
                                  ),
                                  FilledButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text('حذف'),
                                  ),
                                ],
                              ),
                            );
                            if (ok != true) return;
                            try {
                              final b = widget.store.db.batch();
                              b.delete(
                                widget.store.db.doc('questions/${q['id']}'),
                              );
                              b.delete(
                                widget.store.db.doc('answerKeys/${q['id']}'),
                              );
                              await b.commit();
                              await widget.store.audit(
                                'question_delete',
                                q['id'],
                              );
                              if (mounted) setState(reload);
                            } catch (e) {
                              if (context.mounted) message(context, e);
                            }
                          },
                    icon: const Icon(Icons.delete_outline),
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}

class AdminQuizResults extends StatefulWidget {
  const AdminQuizResults({super.key, required this.store, required this.quiz});
  final SibStore store;
  final RowData quiz;
  @override
  State<AdminQuizResults> createState() => _AdminQuizResultsState();
}

class _AdminQuizResultsState extends State<AdminQuizResults> {
  late Future<List<RowData>> rows;
  @override
  void initState() {
    super.initState();
    reload();
  }

  void reload() {
    rows = widget.store.list(
      'attempts',
      field: 'quiz_id',
      equalTo: widget.quiz['id'],
    );
  }

  Future<void> grade(RowData attempt) async {
    final questions = await widget.store.list(
      'questions',
      field: 'quiz_id',
      equalTo: widget.quiz['id'],
    );
    final data = <RowData>[];
    final fields = <EditField>[];
    final initial = <String, dynamic>{};
    num total = 0;
    for (final q in questions) {
      final key =
          (await widget.store.db.doc('answerKeys/${q['id']}').get()).data() ??
          {};
      final answer = (attempt['answers'] as Map? ?? {})[q['id']];
      final choices = List<String>.from(q['choices'] ?? []);
      final correct = (key['correct_index'] as num?)?.toInt() ?? -1;
      final selected = answer is num ? answer.toInt() : -1;
      final points = q['points'] as num;
      total += points;
      final score = q['type'] == 'mcq' && selected == correct ? points : 0;
      data.add({
        'id': q['id'],
        'prompt': q['prompt'],
        'answer': q['type'] == 'mcq'
            ? (selected >= 0 && selected < choices.length
                  ? choices[selected]
                  : 'بدون إجابة')
            : '${answer ?? ''}',
        'model': q['type'] == 'mcq'
            ? (correct >= 0 && correct < choices.length ? choices[correct] : '')
            : key['model_answer'] ?? '',
        'score': score,
        'points': points,
      });
      initial[q['id']] = score;
      fields.add(
        EditField(
          q['id'],
          '${text(q, 'prompt')} — الإجابة: ${data.last['answer']} — من $points',
          number: true,
        ),
      );
    }
    fields.add(const EditField('feedback', 'ملاحظات للطالب', multiline: true));
    if (!mounted) return;
    await editRecord(
      context,
      'تصحيح — الاختيار محسوب والمقالي تراجعه',
      fields,
      initial,
      (d) async {
        num score = 0;
        for (final item in data) {
          final value = d[item['id']] as num;
          if (value < 0 || value > (item['points'] as num))
            throw StateError('درجة السؤال تتجاوز الحد');
          item['score'] = value;
          score += value;
        }
        await widget.store.gradeAttempt(attempt['id'], {
          'uid': attempt['uid'],
          'quiz_id': attempt['quiz_id'],
          'course_id': attempt['course_id'],
          'score': score,
          'total': total,
          'feedback': text(d, 'feedback'),
          'items': data,
        });
      },
    );
    if (mounted) setState(reload);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('التصحيح والنتائج')),
    body: FutureBuilder<List<RowData>>(
      future: rows,
      builder: (context, snap) {
        if (!snap.hasData)
          return const Center(child: CircularProgressIndicator());
        return ListView(
          padding: const EdgeInsets.all(18),
          children: [
            const Text(
              'التصحيح يتم من حسابك: درجات الاختيار تُحسب تلقائيًا عند فتح ورقة الطالب، والمقالي تضع درجته ثم تحفظ. النتائج لا تظهر إلا عند تفعيل عرضها.',
            ),
            for (final a in snap.data!)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SelectableText(text(a, 'uid')),
                      Text(
                        a['submitted_at'] == null
                            ? 'لم يسلّم بعد'
                            : 'تم التسليم ${dateLabel(a['submitted_at'])}',
                      ),
                      if (a['submitted_at'] != null)
                        FilledButton(
                          onPressed: () => grade(a),
                          child: const Text('افتح الورقة وصحّح'),
                        ),
                      TextButton(
                        onPressed: () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('السماح بمحاولة جديدة؟'),
                              content: const Text(
                                'سيتم حذف المحاولة والدرجة القديمة لهذا الطالب في هذا الاختبار.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('إلغاء'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('تأكيد'),
                                ),
                              ],
                            ),
                          );
                          if (ok != true) return;
                          try {
                            await widget.store.resetAttempt(a['id']);
                            if (mounted) setState(reload);
                          } catch (e) {
                            if (context.mounted) message(context, e);
                          }
                        },
                        child: const Text('إعادة فتح محاولة'),
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
