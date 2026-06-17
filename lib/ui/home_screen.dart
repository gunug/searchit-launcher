import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../models/app_entry.dart';
import '../models/badge.dart';
import '../search/search_engine.dart';
import '../services/app_service.dart';
import '../services/donation_service.dart';
import '../services/storage_service.dart';
import 'app_tile.dart';

/// 두 페이지로 구성된 런처 홈.
/// 왼쪽(0): 빈도순 전체 앱 그리드 (사용/미사용 섹션 분리)
/// 오른쪽(1): 검색창 + 최근 사용
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  static const _gridDelegate = SliverGridDelegateWithMaxCrossAxisExtent(
    maxCrossAxisExtent: 90,
    mainAxisExtent: 100,
  );

  final _searchController = TextEditingController();
  final _pageController = PageController();

  // 기본 홈 앱(집모양) 버튼 강조용 깜빡임. 정지(rest) 상태에서는 controller 값이
  // 0.0 → 페이드 1.0 / 스케일 1.0(평상시 모습)이 된다.
  late final AnimationController _blinkController;
  late final Animation<double> _blinkFade;
  late final Animation<double> _blinkScale;

  List<AppEntry> _apps = [];
  Map<String, AppEntry> _byPackage = {};
  List<HistoryEntry> _history = [];
  List<String> _recents = [];
  Map<String, List<DateTime>> _launchHistory = {};
  Set<String> _dayBadgeEarned = {};
  Set<String> _newBadgeDismissed = {};
  Set<String> _lockedApps = {};

  String _query = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    final curve = CurvedAnimation(
      parent: _blinkController,
      curve: Curves.easeInOut,
    );
    _blinkFade = Tween<double>(begin: 1.0, end: 0.35).animate(curve);
    _blinkScale = Tween<double>(begin: 1.0, end: 1.3).animate(curve);

    _load();
    AppService.setOnPackageChanged(_onPackageChanged);
    DonationService.init();
    DonationService.setOnResult((success) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(success ? tr.donationThanks : tr.purchaseFailed),
      ));
    });

    // 첫 실행 플로우(언어 선택 → 튜토리얼)는 한 번만 수행.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeRunFirstRun());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AppService.setOnPackageChanged(null);
    _searchController.dispose();
    _pageController.dispose();
    _blinkController.dispose();
    DonationService.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // 첫 실행 플로우 + 언어 설정 + 깜빡임
  // ---------------------------------------------------------------------------

  /// 첫 실행이면 언어를 먼저 고르게 하고, 이어서 기본 홈 앱 튜토리얼을 띄운다.
  Future<void> _maybeRunFirstRun() async {
    final savedLang = await StorageService.loadLanguage();
    if (!mounted) return;
    if (savedLang == null) {
      await _showLanguageDialog(firstRun: true);
      if (!mounted) return;
    }

    if (await StorageService.isHomeGuideShown()) return;
    if (!mounted) return;
    await _showHomeGuideDialog();
  }

  /// 언어 선택 다이얼로그. 첫 실행 시엔 닫기 불가(반드시 선택).
  Future<void> _showLanguageDialog({required bool firstRun}) async {
    var selected = appLang.value;
    await showDialog<void>(
      context: context,
      barrierDismissible: !firstRun,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          // 첫 실행 땐 아직 언어가 확정되지 않았으니 병기 라벨로 안내.
          title: Text(firstRun ? '언어 / Language' : tr.language),
          content: RadioGroup<AppLang>(
            groupValue: selected,
            onChanged: (v) {
              if (v != null) setDialogState(() => selected = v);
            },
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RadioListTile<AppLang>(
                  value: AppLang.ko,
                  title: Text('한국어'),
                  contentPadding: EdgeInsets.zero,
                ),
                RadioListTile<AppLang>(
                  value: AppLang.en,
                  title: Text('English'),
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () async {
                await StorageService.saveLanguage(selected);
                appLang.value = selected;
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: Text(firstRun ? '확인 / OK' : tr.ok),
            ),
          ],
        ),
      ),
    );
  }

  /// 기본 홈 앱 안내(튜토리얼). 확인을 누르면 집모양 버튼 깜빡임을 시작한다.
  Future<void> _showHomeGuideDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.home_outlined),
            const SizedBox(width: 8),
            Expanded(child: Text(tr.tutorialTitle)),
          ],
        ),
        content: Text(tr.tutorialBody, style: const TextStyle(height: 1.4)),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr.ok),
          ),
        ],
      ),
    );
    await StorageService.markHomeGuideShown();
    if (mounted) _startBlink();
  }

  void _startBlink() => _blinkController.repeat(reverse: true);

  void _stopBlink() {
    if (!_blinkController.isAnimating) return;
    _blinkController
      ..stop()
      ..reset(); // 평상시 모습(페이드 1.0 / 스케일 1.0)으로 복귀
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    // 30일 미사용 앱 기록 자동 정리 (SharedPreferences 첫 초기화도 여기서 수행)
    await StorageService.pruneStaleRecords();

    // 모든 storage 읽기 + native 메타데이터 쿼리를 동시에 시작
    final cachedAppsF = StorageService.loadCachedApps();
    final historyF = StorageService.loadHistory();
    final recentsF = StorageService.loadRecents();
    final rawHistoryF = StorageService.loadLaunchHistory();
    final dayBadgeF = StorageService.loadDayBadgeEarned();
    final newBadgeDismissedF = StorageService.loadNewBadgeDismissed();
    final lockedAppsF = StorageService.loadLockedApps();
    final metadataF = AppService.getAppsMetadata();

    // storage는 native보다 빠르게 완료됨
    final cachedApps = await cachedAppsF;
    final history = await historyF;
    final recents = await recentsF;
    final rawHistory = await rawHistoryF;
    var dayBadgeEarned = await dayBadgeF;
    final newBadgeDismissed = await newBadgeDismissedF;
    final lockedApps = await lockedAppsF;

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
        _dayBadgeEarned = dayBadgeEarned;
        _newBadgeDismissed = newBadgeDismissed;
        _lockedApps = lockedApps;
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
      _newBadgeDismissed = newBadgeDismissed;
      _lockedApps = lockedApps;
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

  /// 다른 앱이 설치/업데이트/삭제될 때 네이티브에서 호출된다.
  /// 업데이트(replaced) 시 네이티브가 이미 디스크 아이콘 캐시를 비웠으므로
  /// 해당 앱 아이콘만 강제로 다시 받아 즉시 교체한다(콜드스타트 대기 불필요).
  Future<void> _onPackageChanged(String pkg, String action) async {
    if (!mounted) return;
    if (action == 'replaced') {
      final icons = await AppService.getIcons([pkg]);
      final icon = icons[pkg];
      if (icon == null || !mounted) return;
      final updated = _apps
          .map((a) => a.packageName == pkg ? a.copyWithIcon(icon) : a)
          .toList();
      setState(() {
        _apps = updated;
        _byPackage = {for (final a in updated) a.packageName: a};
      });
    } else {
      // 설치 / 삭제 → 목록 전체 재로드
      await _load();
    }
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

  Future<void> _clearRecord(String packageName) async {
    await StorageService.clearAppRecord(packageName);
    await _load();
  }

  Future<void> _toggleLock(String packageName) async {
    final updated = Set<String>.from(_lockedApps);
    if (updated.contains(packageName)) {
      updated.remove(packageName);
    } else {
      updated.add(packageName);
    }
    await StorageService.saveLockedApps(updated);
    setState(() => _lockedApps = updated);
  }

  bool _showNewBadge(AppEntry app) =>
      app.isNew && !_newBadgeDismissed.contains(app.packageName);

  // ---------------------------------------------------------------------------
  // 빈도 정렬: new 배지 앱 최우선 → day 배지 → Σ 1/(1+경과일) → 라벨순
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
        // 1순위: new 배지 (dismissed 제외)
        final newCmp = (_showNewBadge(b.$1) ? 1 : 0).compareTo(_showNewBadge(a.$1) ? 1 : 0);
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

  (List<AppEntry>, List<AppEntry>, List<AppEntry>) _splitApps() {
    final sorted = _frequentAppsSorted();
    final newAndLocked = <AppEntry>[];
    final used = <AppEntry>[];
    final unused = <AppEntry>[];

    for (final app in sorted) {
      if (_lockedApps.contains(app.packageName) || _showNewBadge(app)) {
        newAndLocked.add(app);
      } else {
        final launches = _launchHistory[app.packageName];
        if (launches != null && launches.isNotEmpty) {
          used.add(app);
        } else {
          unused.add(app);
        }
      }
    }

    return (newAndLocked, used, unused);
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
  // 왼쪽 페이지: 빈도순 전체 앱 (사용/미사용 섹션)
  // ---------------------------------------------------------------------------

  Widget _buildFrequentPage() {
    final (newAndLocked, used, unused) = _splitApps();
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _pageTitle(tr.appList)),
        if (newAndLocked.isNotEmpty) ...[
          SliverToBoxAdapter(child: _sectionHeader(tr.sectionNewLock)),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            sliver: SliverGrid(
              gridDelegate: _gridDelegate,
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final app = newAndLocked[i];
                  final locked = _lockedApps.contains(app.packageName);
                  return AppTile(
                    app: app,
                    showLockBadge: locked,
                    showNewBadge: !locked && _showNewBadge(app),
                    showDayBadge: false,
                    isLocked: locked,
                    onTap: () => _launch(app, recordAsRecent: true),
                    onClearRecord: () => _clearRecord(app.packageName),
                    onToggleLock: () => _toggleLock(app.packageName),
                  );
                },
                childCount: newAndLocked.length,
              ),
            ),
          ),
        ],
        if (used.isNotEmpty) ...[
          SliverToBoxAdapter(child: _sectionHeader(tr.sectionUsed)),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            sliver: SliverGrid(
              gridDelegate: _gridDelegate,
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final app = used[i];
                  return AppTile(
                    app: app,
                    showNewBadge: false,
                    showDayBadge: _dayBadgeEarned.contains(app.packageName),
                    isLocked: false,
                    onTap: () => _launch(app, recordAsRecent: true),
                    onClearRecord: () => _clearRecord(app.packageName),
                    onToggleLock: () => _toggleLock(app.packageName),
                  );
                },
                childCount: used.length,
              ),
            ),
          ),
        ],
        if (unused.isNotEmpty) ...[
          SliverToBoxAdapter(child: _sectionHeader(tr.sectionUnused)),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
            sliver: SliverGrid(
              gridDelegate: _gridDelegate,
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final app = unused[i];
                  return Opacity(
                    opacity: 0.6,
                    child: AppTile(
                      app: app,
                      showNewBadge: false,
                      showDayBadge: false,
                      isLocked: false,
                      onTap: () => _launch(app, recordAsRecent: true),
                      onClearRecord: () => _clearRecord(app.packageName),
                      onToggleLock: () => _toggleLock(app.packageName),
                    ),
                  );
                },
                childCount: unused.length,
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 오른쪽 페이지: 검색창 + 최근 사용
  // ---------------------------------------------------------------------------

  Widget _buildSearchPage() {
    return Column(
      children: [
        _pageTitle(tr.recentSearch),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: TextField(
            controller: _searchController,
            autofocus: false,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: tr.searchHint,
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
      return Center(
        child: Text(
          tr.enterSearchTerm,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.grey),
        ),
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
                return AppTile(
                  app: app,
                  showLockBadge: _lockedApps.contains(app.packageName),
                  showNewBadge: !_lockedApps.contains(app.packageName) && _showNewBadge(app),
                  showDayBadge: _dayBadgeEarned.contains(app.packageName),
                  isLocked: _lockedApps.contains(app.packageName),
                  onTap: () => _launch(app),
                  onClearRecord: () => _clearRecord(app.packageName),
                  onToggleLock: () => _toggleLock(app.packageName),
                );
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
      return Center(
        child: Text(tr.noResults, style: const TextStyle(color: Colors.grey)),
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
                  showLockBadge: _lockedApps.contains(app.packageName),
                  showNewBadge: !_lockedApps.contains(app.packageName) && _showNewBadge(app),
                  showDayBadge: _dayBadgeEarned.contains(app.packageName),
                  isLocked: _lockedApps.contains(app.packageName),
                  onTap: () => _launch(
                    app,
                    historyKeyword: _searchController.text,
                    recordAsRecent: true,
                  ),
                  onClearRecord: () => _clearRecord(app.packageName),
                  onToggleLock: () => _toggleLock(app.packageName),
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

  Future<void> _showDonationDialog() async {
    final products = DonationService.products;
    if (products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr.loadingPurchase)),
      );
      return;
    }

    var selected = 0;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(tr.supportTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                tr.supportBody,
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 16),
              RadioGroup<int>(
                groupValue: selected,
                onChanged: (v) {
                  if (v != null) setDialogState(() => selected = v);
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(products.length, (i) {
                    final p = products[i];
                    return RadioListTile<int>(
                      value: i,
                      title: Text(DonationService.labelFor(p.id)),
                      secondary: Text(
                        p.price,
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
              child: Text(tr.cancel),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                DonationService.buy(products[selected]);
              },
              child: Text(tr.supportShort),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurface.withAlpha(160),
        ),
      ),
    );
  }

  Widget _pageTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 4, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.left,
              style: const TextStyle(
                  fontSize: 22, fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: tr.settings,
            onPressed: () => _showLanguageDialog(firstRun: false),
          ),
          // 집모양 버튼 — 튜토리얼 직후 페이드+스케일로 깜빡이며, 누르면 정지한다.
          FadeTransition(
            opacity: _blinkFade,
            child: ScaleTransition(
              scale: _blinkScale,
              child: IconButton(
                icon: const Icon(Icons.home_outlined),
                tooltip: tr.homeSettingsTooltip,
                onPressed: () {
                  _stopBlink();
                  AppService.openHomeSettings();
                },
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.favorite_border),
            tooltip: tr.supportTitle,
            onPressed: _showDonationDialog,
          ),
        ],
      ),
    );
  }
}
