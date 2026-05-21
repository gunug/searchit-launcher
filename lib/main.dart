import 'package:flutter/material.dart';

import 'ui/home_screen.dart';

void main() {
  runApp(const SearchItApp());
}

class SearchItApp extends StatelessWidget {
  const SearchItApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SearchIt',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.tealAccent,
          brightness: Brightness.dark,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
