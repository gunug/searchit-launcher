import 'package:flutter/material.dart';

import '../models/app_entry.dart';
import '../models/badge.dart';
import '../search/search_engine.dart';
import '../services/app_service.dart';
import '../services/storage_service.dart';
import 'app_tile.dart';

/// The launcher home screen: a search box over a ranked results grid,
/// or the default view (최근 사용 + 자주 사용) when the query is empty.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  // Change _crossAxisCount to adjust the grid width everywhere at once.
  static const int _crossAxisCount = 4;
  // Number of rows shown in the 최근 사용 section.
  static const int _recentRows = 3;

  static const _gridDelegate = SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: _crossAxisCount,
    childAspectRatio: 0.78,
  );

  final _controller = TextEditingController();

  List<AppEntry> _apps = [];
  final Map<String, AppEntry> _byPackage = {};
  List<HistoryEntry> _history = [];
  List<String> _recents = [];
  Map<String, List<DateTime>> _launchHistory = {};
  Set<String> _dayBadgeEarned = {};

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
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final apps = await AppService.getApps();
    final history = await StorageService.loadHistory();
    final recents = await StorageService.loadRecents();
    final rawHistory = await StorageService.loadLaunchHistory();
    var dayBadgeEarned = await StorageService.loadDayBadgeEarned();

    final launchHistory = rawHistory.map(
      (k, v) => MapEntry(
        k,
        v.map((ts) => DateTime.fromMillisecondsSinceEpoch(ts)).toList(),
      ),
    );

    // Update dayBadgeEarned: grant acquisition or revoke maintenance for each app.
    bool earnedChanged = false;
    for (final app in apps) {
      final launches = launchHistory[app.packageName] ?? [];
      final currentlyEarned = dayBadgeEarned.contains(app.packageName);
      final badge = BadgeService.calculate(app, launches, currentlyEarned);
      if (badge == AppBadge.day && !currentlyEarned) {
        dayBadgeEarned.add(app.packageName);
        earnedChanged = true;
      } else if (badge != AppBadge.day && currentlyEarned) {
        dayBadgeEarned.remove(app.packageName);
        earnedChanged = true;
      }
    }
    if (earnedChanged) await StorageService.saveDayBadgeEarned(dayBadgeEarned);

    if (!mounted) return;
    setState(() {
      _apps = apps;
      _byPackage
        ..clear()
        ..addEntries(apps.map((a) => MapEntry(a.packageName, a)));
      _history = history;
      _recents = recents;
      _launchHistory = launchHistory;
      _dayBadgeEarned = dayBadgeEarned;
      _loading = false;
    });
  }

  /// Launches [app].
  ///
  /// [recordAsRecent] — set true only when launching from search results so
  /// that the 최근 사용 list tracks search-driven launches exclusively.
  Future<void> _launch(
    AppEntry app, {
    String? historyKeyword,
    bool recordAsRecent = false,
  }) async {
    if (recordAsRecent) {
      await StorageService.recordLaunch(app.packageName);
    }
    await StorageService.recordLaunchTimestamp(app.packageName);
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
              padding: const EdgeInsets.fromLTRB(12, 12, 8, 8),
              child: Row(
                children: [
                  Expanded(
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
                        contentPadding: EdgeInsets.zero,
                      ),
                      onChanged: (value) => setState(() => _query = value),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.home_outlined),
                    tooltip: '기본 런처 설정',
                    onPressed: AppService.openHomeSettings,
                  ),
                  IconButton(
                    icon: const Icon(Icons.favorite_border),
                    tooltip: '후원하기',
                    onPressed: _showDonationDialog,
                  ),
                ],
              ),
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return _query.trim().isEmpty ? _buildDefault() : _buildResults();
  }

  // ---------------------------------------------------------------------------
  // Donation dialog
  // ---------------------------------------------------------------------------

  static const _donationOptions = [
    ('커피 한 잔', '1,100원'),
    ('음료 한 잔', '3,300원'),
    ('식사 한 끼', '5,500원'),
    ('큰 후원', '11,000원'),
  ];

  Future<void> _showDonationDialog() async {
    var selected = 0;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('후원하기'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '앱이 유용하셨다면 제작자에게 응원을 보내주세요 🙏',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 16),
              RadioGroup<int>(
                groupValue: selected,
                onChanged: (v) {
                  if (v != null) setDialogState(() => selected = v);
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(_donationOptions.length, (i) {
                    final (label, price) = _donationOptions[i];
                    return RadioListTile<int>(
                      value: i,
                      title: Text(label),
                      secondary: Text(
                        price,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    );
                  }),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () {
                // TODO: 인앱결제 연동 후 실제 구매 처리
                Navigator.pop(ctx);
              },
              child: const Text('후원'),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Default view (empty query)
  // ---------------------------------------------------------------------------

  Widget _buildDefault() {
    final recentApps = _recents
        .map((pkg) => _byPackage[pkg])
        .whereType<AppEntry>()
        .take(_crossAxisCount * _recentRows)
        .toList();

    final frequentApps = _frequentAppsSorted();

    if (recentApps.isEmpty && frequentApps.isEmpty) {
      return const Center(
        child: Text('검색어를 입력하세요', style: TextStyle(color: Colors.grey)),
      );
    }

    return CustomScrollView(
      slivers: [
        if (recentApps.isNotEmpty) ..._sectionSlivers('최근 사용', recentApps),
        if (frequentApps.isNotEmpty) ..._sectionSlivers('자주 사용', frequentApps),
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
      ],
    );
  }

  /// All apps that have been launched through this launcher, capped at 40.
  /// Sort order: badge priority (newApp > day > none) → weighted score → last launch.
  List<AppEntry> _frequentAppsSorted() {
    const maxApps = 40;
    final entries = <(AppEntry, AppBadge, double, DateTime)>[];

    for (final app in _apps) {
      final launches = _launchHistory[app.packageName] ?? [];
      if (launches.isEmpty && !app.isNew) continue;
      final badge = BadgeService.calculate(
          app, launches, _dayBadgeEarned.contains(app.packageName));
      final score = BadgeService.weightedScore(launches);
      final last = launches.isEmpty
          ? DateTime(0)
          : launches.reduce((a, b) => a.isAfter(b) ? a : b);
      entries.add((app, badge, score, last));
    }

    entries.sort((a, b) {
      // Higher enum index = higher priority (newApp=2 > day=1 > none=0).
      final bp = b.$2.index.compareTo(a.$2.index);
      if (bp != 0) return bp;
      // More recent / frequent launches win.
      final sp = b.$3.compareTo(a.$3);
      if (sp != 0) return sp;
      // Tie-break: most recently launched first.
      return b.$4.compareTo(a.$4);
    });

    return entries.take(maxApps).map((e) => e.$1).toList();
  }

  // ---------------------------------------------------------------------------
  // Search results view
  // ---------------------------------------------------------------------------

  Widget _buildResults() {
    final results = SearchEngine.search(_controller.text, _apps, _history);
    if (results.isEmpty) {
      return const Center(
        child: Text('검색 결과 없음', style: TextStyle(color: Colors.grey)),
      );
    }
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          sliver: SliverGrid(
            gridDelegate: _gridDelegate,
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final app = results[i];
                return AppTile(
                  app: app,
                  onTap: () => _launch(
                    app,
                    historyKeyword: _controller.text,
                    recordAsRecent: true,
                  ),
                );
              },
              childCount: results.length,
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Shared helpers
  // ---------------------------------------------------------------------------

  List<Widget> _sectionSlivers(String title, List<AppEntry> apps) {
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
              return AppTile(app: app, onTap: () => _launch(app));
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
