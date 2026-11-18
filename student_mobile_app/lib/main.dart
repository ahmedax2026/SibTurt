// SPDX-FileCopyrightText: 2026 Ahmed Elwakeel
// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:universal_youtube_player/universal_youtube_player.dart';
import 'package:flutter/services.dart';
import 'sibawayh/store.dart';
import 'sibawayh/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  UniversalYoutubePlayerBootstrap.ensureInitialized();
  await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  final store = SibStore();
  await store.initialize();
  runApp(SibawayhApp(store: store));
}
