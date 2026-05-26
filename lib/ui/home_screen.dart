import 'package:flutter/material.dart';

import '../models/app_entry.dart';
import '../models/badge.dart';
import '../search/search_engine.dart';
import '../services/app_service.dart';
import '../services/storage_service.dart';
import 'app_tile.dart';

/// 두 페이지로 구성된 런처 홈.
/// 왼쪽(0): 빈도순 전체 앱 그리드
/// 오른쪽(1): 검색창 + 최근 사용
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  static const int _crossAxisCount = 4;

  static const _gridDelegate = SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: _crossAxisCount,
    childAspectRatio: 0.78,
  );

  final _searchController = TextEditingController();
  final _pageController = PageController();

  List<AppEntry> _apps = [];
  Map<String, AppEntry> _byPackage = {};
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
    _searchController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    // 모든 storage 읽기 + native 메타데이터 쿼리를 동시에 시작
    final cachedAppsF = StorageService.loadCachedApps();
    final historyF = StorageService.loadHistory();
    final recentsF = StorageService.loadRecents();
    final rawHistoryF = StorageService.loadLaunchHistory();
    final dayBadgeF = StorageService.loadDayBadgeEarned();
    final metadataF = AppService.getAppsMetadata();

    // storage는 native보다 빠르게 완료됨
    final cachedApps = await cachedAppsF;
    final history = await historyF;
    final recents = await recentsF;
    final rawHistory = await rawHistoryF;
    var dayBadgeEarned = await dayBadgeF;

    final launchHistory = rawHistory.map(
      (k, v) => MapEntry(
        k,
        v.map((ts) => DateTime.fromMillisecondsSinceEpoch(ts)).toList(),
      ),
    );

    // Phase 1: 캐시된 메타데이터로 즉시 UI 표시 (아이콘은 placeholder)
    if (_loading && cachedApps.isNotEmpty && mounted) {
      setState(() {
        _apps = cachedApps;
        _byPackage = {for (final a in cachedApps) a.packageName: a};
        _history = history;
        _recents = recents;
        _launchHistory = launchHistory;
        _loading = false;
      });
    }

    // Phase 2: native 메타데이터 완료 후 앱 목록 갱신
    final freshMeta = await metadataF;
    await StorageService.saveCachedApps(freshMeta);

    // 이미 메모리에 있는 아이콘 재활용 (resume 시 깜빡임 방지)
    final existingIcons = {
      for (final a in _apps)
        if (a.icon != null) a.packageName: a.icon!
    };
    final merged =
        freshMeta.map((a) => a.copyWithIcon(existingIcons[a.packageName])).toList();

    // 뱃지 획득/상실 갱신
    var badgeChanged = false;
    for (final app in freshMeta) {
      final launches = launchHistory[app.packageName] ?? [];
      final earned = dayBadgeEarned.contains(app.packageName);
      if (!earned && BadgeService.hasEarned(launches)) {
        dayBadgeEarned.add(app.packageName);
        badgeChanged = true;
      } else if (earned && BadgeService.shouldRevoke(launches)) {
        dayBadgeEarned.remove(app.packageName);
        badgeChanged = true;
      }
    }
    if (badgeChanged) await StorageService.saveDayBadgeEarned(dayBadgeEarned);

    if (!mounted) return;
    setState(() {
      _apps = merged;
      _byPackage = {for (final a in merged) a.packageName: a};
      _history = history;
      _recents = recents;
      _launchHistory = launchHistory;
      _dayBadgeEarned = dayBadgeEarned;
      _loading = false;
    });

    // Phase 3: 아이콘 없는 앱만 병렬로 로드 (첫 실행 / 신규 앱)
    final needIcons = freshMeta
        .where((a) => !existingIcons.containsKey(a.packageName))
        .map((a) => a.packageName)
        .toList();
    if (needIcons.isEmpty) return;

    final newIcons = await AppService.getIcons(needIcons);
    if (!mounted) return;

    final finalApps = _apps.map((a) {
      final icon = newIcons[a.packageName];
      return icon != null ? a.copyWithIcon(icon) : a;
    }).toList();

    setState(() {
      _apps = finalApps;
      _byPackage = {for (final a in finalApps) a.packageName: a};
    });
  }

  Future<void> _launch(
    AppEntry app, {
    String? historyKeyword,
    bool recordAsRecent = false,
  }) async {
    if (recordAsRecent) await StorageService.recordLaunch(app.packageName);
    await StorageService.recordLaunchTimestamp(app.packageName);
    final keyword = historyKeyword?.trim() ?? '';
    if (keyword.isNotEmpty) {
      await StorageService.recordHistory(keyword, app.packageName);
    }
    await AppService.launch(app.packageName);
  }

  // ---------------------------------------------------------------------------
  // 빈도 정렬: new 배지 앱 최우선 → Σ 1/(1+경과일) → 라벨순
  // ---------------------------------------------------------------------------

  List<AppEntry> _frequentAppsSorted() {
    final now = DateTime.now();

    double weightedScore(List<DateTime> launches) => launches.fold(0.0, (sum, l) {
          final daysAgo =
              now.difference(l).inMicroseconds / Duration.microsecondsPerDay;
          return sum + 1.0 / (1.0 + daysAgo);
        });

    final scored = _apps.map((app) {
      final score = weightedScore(_launchHistory[app.packageName] ?? []);
      return (app, score);
    }).toList()
      ..sort((a, b) {
        // 1순위: new 배지
        final newCmp = (b.$1.isNew ? 1 : 0).compareTo(a.$1.isNew ? 1 : 0);
        if (newCmp != 0) return newCmp;
        // 2순위: day 배지
        final dayCmp = (_dayBadgeEarned.contains(b.$1.packageName) ? 1 : 0)
            .compareTo(_dayBadgeEarned.contains(a.$1.packageName) ? 1 : 0);
        if (dayCmp != 0) return dayCmp;
        // 3순위: 빈도 점수
        final c = b.$2.compareTo(a.$2);
        if (c != 0) return c;
        return a.$1.label.toLowerCase().compareTo(b.$1.label.toLowerCase());
      });

    return scored.map((e) => e.$1).toList();
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: PageView(
          controller: _pageController,
          children: [
            _buildFrequentPage(),
            _buildSearchPage(),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 왼쪽 페이지: 빈도순 전체 앱
  // ---------------------------------------------------------------------------

  Widget _buildFrequentPage() {
    final sorted = _frequentAppsSorted();
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _pageTitle('앱 목록', 'Apps')),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
          sliver: SliverGrid(
            gridDelegate: _gridDelegate,
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final app = sorted[i];
                return AppTile(
                  app: app,
                  onTap: () => _launch(app),
                  showDayBadge: _dayBadgeEarned.contains(app.packageName),
                );
              },
              childCount: sorted.length,
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 오른쪽 페이지: 검색창 + 최근 사용
  // ---------------------------------------------------------------------------

  Widget _buildSearchPage() {
    return Column(
      children: [
        _pageTitle('최근 & 검색', 'Recent & Search'),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: TextField(
            controller: _searchController,
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
                        _searchController.clear();
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
        Expanded(
          child: _query.trim().isEmpty ? _buildRecents() : _buildResults(),
        ),
      ],
    );
  }

  Widget _buildRecents() {
    final recentApps = _recents
        .map((pkg) => _byPackage[pkg])
        .whereType<AppEntry>()
        .toList();

    if (recentApps.isEmpty) {
      return const Center(
        child: Text('검색어를 입력하세요', style: TextStyle(color: Colors.grey)),
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
                final app = recentApps[i];
                return AppTile(app: app, onTap: () => _launch(app));
              },
              childCount: recentApps.length,
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
      ],
    );
  }

  Widget _buildResults() {
    final results =
        SearchEngine.search(_searchController.text, _apps, _history);
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
                    historyKeyword: _searchController.text,
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
                '앱이 유용하셨다면 제작자에게 응원을 보내주세요',
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
                        style:
                            const TextStyle(fontWeight: FontWeight.bold),
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
              onPressed: () => Navigator.pop(ctx),
              child: const Text('후원'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pageTitle(String ko, String en) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 4, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ko,
                  textAlign: TextAlign.left,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold),
                ),
                Text(
                  en,
                  textAlign: TextAlign.left,
                  style: TextStyle(
                    fontSize: 13,
                    color:
                        Theme.of(context).colorScheme.onSurface.withAlpha(128),
                  ),
                ),
              ],
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
    );
  }
}
