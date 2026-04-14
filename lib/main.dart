import 'package:flutter/material.dart';
import 'app/theme.dart';
import 'screens/world_list_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const WordSearchApp());
}

class WordSearchApp extends StatelessWidget {
  const WordSearchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Word Search',
      theme: buildAppTheme(),
      home: const WorldListScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
