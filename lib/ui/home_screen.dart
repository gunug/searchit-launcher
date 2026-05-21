import 'package:flutter/material.dart';

import '../models/app_entry.dart';
import '../search/search_engine.dart';
import '../services/app_service.dart';
import '../services/storage_service.dart';
import 'app_tile.dart';

/// The launcher home screen: a search box over four classified result
/// sections, or the recent-apps list when the query is empty.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  /// Apps are shown several per row in a grid.
  static const _gridDelegate = SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: 4,
    childAspectRatio: 0.78,
  );

  final _controller = TextEditingController();

  List<AppEntry> _apps = [];
  final Map<String, AppEntry> _byPackage = {};
  List<HistoryEntry> _history = [];
  List<String> _recents = [];

  String _query = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Returning to the launcher: pick up installs/uninstalls and new history.
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final apps = await AppService.getApps();
    final history = await StorageService.loadHistory();
    final recents = await StorageService.loadRecents();
    if (!mounted) return;
    setState(() {
      _apps = apps;
      _byPackage
        ..clear()
        ..addEntries(apps.map((a) => MapEntry(a.packageName, a)));
      _history = history;
      _recents = recents;
      _loading = false;
    });
  }

  Future<void> _launch(AppEntry app, {String? historyKeyword}) async {
    await StorageService.recordLaunch(app.packageName);
    final keyword = historyKeyword?.trim() ?? '';
    if (keyword.isNotEmpty) {
      await StorageService.recordHistory(keyword, app.packageName);
    }
    await AppService.launch(app.packageName);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _controller,
                autofocus: false,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: '앱 검색',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _controller.clear();
                            setState(() => _query = '');
                          },
                        ),
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(28),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return _query.trim().isEmpty ? _buildRecents() : _buildResults();
  }

  /// Empty-query view: apps recently launched through this launcher.
  Widget _buildRecents() {
    final apps = _recents
        .map((pkg) => _byPackage[pkg])
        .whereType<AppEntry>()
        .toList();
    if (apps.isEmpty) {
      return const Center(
        child: Text('검색어를 입력하세요', style: TextStyle(color: Colors.grey)),
      );
    }
    return CustomScrollView(
      slivers: [
        ..._sectionSlivers('최근 사용', apps),
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
      ],
    );
  }

  /// Query view: the four classified sections in fixed display order.
  Widget _buildResults() {
    final results = SearchEngine.search(_controller.text, _apps, _history);
    if (results.isEmpty) {
      return const Center(
        child: Text('검색 결과 없음', style: TextStyle(color: Colors.grey)),
      );
    }
    return CustomScrollView(
      slivers: [
        ..._sectionSlivers('일치 · match', results.match),
        ..._sectionSlivers('이력 · history', results.history),
        ..._sectionSlivers('유사 · similar', results.similar,
            isHistorySource: true),
        ..._sectionSlivers('관련 · related', results.related,
            isHistorySource: true),
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
      ],
    );
  }

  /// Builds the header + app grid for one section; [isHistorySource]
  /// sections record a history keyword on launch (similar / related).
  List<Widget> _sectionSlivers(String title, List<AppEntry> apps,
      {bool isHistorySource = false}) {
    if (apps.isEmpty) return const [];
    return [
      SliverToBoxAdapter(child: _sectionHeader(title)),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        sliver: SliverGrid(
          gridDelegate: _gridDelegate,
          delegate: SliverChildBuilderDelegate(
            (context, i) {
              final app = apps[i];
              return AppTile(
                app: app,
                onTap: () => _launch(
                  app,
                  historyKeyword: isHistorySource ? _controller.text : null,
                ),
              );
            },
            childCount: apps.length,
          ),
        ),
      ),
    ];
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
