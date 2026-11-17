// SPDX-FileCopyrightText: 2026 Ahmed Elwakeel
// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tutorloom/sibawayh/app.dart';
import 'package:tutorloom/sibawayh/store.dart';

void main(){
  test('unconfigured Firebase cannot register or grant owner access',()async{
    final store=SibStore();await store.initialize();expect(store.ready,false);expect(store.owner,false);
    expect(()=>store.requireOwner(),throwsStateError);
    await expectLater(store.register('أحمد محمد','01012345678',initialGrades.first,'a@example.test','long-password'),throwsStateError);
    store.dispose();
  });
  testWidgets('Arabic branded welcome opens real registration fields without host prompt',(tester)async{
    tester.view.physicalSize=const Size(430,932);tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
    final store=SibStore();await store.initialize();
    await tester.pumpWidget(SibawayhApp(store:store));await tester.pumpAndSettle();
    expect(find.text('ابدأ رحلتك'),findsOneWidget);expect(find.text('معاينة قبل ربط Firebase'),findsOneWidget);
    await tester.tap(find.text('ابدأ رحلتك'));await tester.pumpAndSettle();
    expect(find.text('الاسم بالكامل'),findsOneWidget);expect(find.text('رقم الموبايل'),findsOneWidget);
    expect(find.text('البريد الإلكتروني'),findsOneWidget);expect(find.text('كلمة المرور'),findsOneWidget);
    expect(find.text('إنشاء الحساب'),findsOneWidget);expect(tester.takeException(),isNull);
    await tester.pumpWidget(const SizedBox.shrink());store.dispose();
  });
}
