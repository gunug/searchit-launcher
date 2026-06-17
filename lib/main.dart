import 'package:flutter/material.dart';

import 'l10n/strings.dart';
import 'services/storage_service.dart';
import 'ui/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 저장된 언어가 있으면 사용, 없으면(첫 실행) 시스템 언어를 기본값으로.
  final saved = await StorageService.loadLanguage();
  appLang.value = saved ?? detectSystemLang();
  runApp(const SearchItApp());
}

class SearchItApp extends StatelessWidget {
  const SearchItApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 언어 변경 시 트리 전체를 다시 그려 모든 문자열을 갱신한다.
    return ValueListenableBuilder<AppLang>(
      valueListenable: appLang,
      builder: (context, _, child) {
        return MaterialApp(
          title: 'Searchit Launcher',
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
      },
    );
  }
}
