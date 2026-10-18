import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/services/library.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await library.load();
  runApp(const ToolPdfViewApp());
}
