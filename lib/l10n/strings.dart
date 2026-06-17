import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// 지원 언어. 경량 커스텀 i18n — 의존성 없이 문자열만 교체한다.
enum AppLang {
  ko('ko'),
  en('en');

  const AppLang(this.code);

  /// SharedPreferences 저장/복원용 코드 ('ko' | 'en').
  final String code;

  static AppLang fromCode(String? code) =>
      AppLang.values.firstWhere((l) => l.code == code, orElse: () => AppLang.en);
}

/// 앱 전역 현재 언어. main.dart에서 MaterialApp을 이 값에 대한
/// [ValueListenableBuilder]로 감싸 언어 변경 시 트리 전체를 다시 그린다.
final ValueNotifier<AppLang> appLang = ValueNotifier<AppLang>(AppLang.en);

/// 현재 언어에 해당하는 문자열 묶음. build/다이얼로그 오픈 시점에 새로 읽는다.
S get tr => S.of(appLang.value);

/// 기기 시스템 언어를 감지한다. 한국어 기기면 ko, 그 외엔 en.
AppLang detectSystemLang() {
  final code = ui.PlatformDispatcher.instance.locale.languageCode;
  return code == 'ko' ? AppLang.ko : AppLang.en;
}

/// 사용자 노출 문자열 모음. 언어별 const 인스턴스(ko/en)로 보관한다.
class S {
  const S({
    required this.appList,
    required this.sectionNewLock,
    required this.sectionUsed,
    required this.sectionUnused,
    required this.recentSearch,
    required this.searchHint,
    required this.enterSearchTerm,
    required this.noResults,
    required this.donationThanks,
    required this.purchaseFailed,
    required this.loadingPurchase,
    required this.supportTitle,
    required this.supportShort,
    required this.supportBody,
    required this.cancel,
    required this.ok,
    required this.close,
    required this.homeSettingsTooltip,
    required this.settings,
    required this.language,
    required this.unlock,
    required this.lock,
    required this.clearHistory,
    required this.delete,
    required this.systemAppCannotUninstall,
    required this.appInfo,
    required this.playStore,
    required this.deleteFailed,
    required this.copied,
    required this.copy,
    required this.donationCoffee,
    required this.donationDrink,
    required this.donationMeal,
    required this.donationBig,
    required this.tutorialTitle,
    required this.tutorialBody,
  });

  final String appList;
  final String sectionNewLock;
  final String sectionUsed;
  final String sectionUnused;
  final String recentSearch;
  final String searchHint;
  final String enterSearchTerm;
  final String noResults;
  final String donationThanks;
  final String purchaseFailed;
  final String loadingPurchase;
  final String supportTitle;
  final String supportShort;
  final String supportBody;
  final String cancel;
  final String ok;
  final String close;
  final String homeSettingsTooltip;
  final String settings;
  final String language;
  final String unlock;
  final String lock;
  final String clearHistory;
  final String delete;
  final String systemAppCannotUninstall;
  final String appInfo;
  final String playStore;
  final String deleteFailed;
  final String copied;
  final String copy;
  final String donationCoffee;
  final String donationDrink;
  final String donationMeal;
  final String donationBig;
  final String tutorialTitle;
  final String tutorialBody;

  static const ko = S(
    appList: '앱 목록',
    sectionNewLock: '신규 & 잠금',
    sectionUsed: '사용',
    sectionUnused: '미사용',
    recentSearch: '최근 & 검색',
    searchHint: '앱 검색',
    enterSearchTerm: '검색어를 입력하세요',
    noResults: '검색 결과 없음',
    donationThanks: '후원 감사합니다!',
    purchaseFailed: '결제에 실패했습니다',
    loadingPurchase: '후원 서비스를 불러오는 중입니다',
    supportTitle: '후원하기',
    supportShort: '후원',
    supportBody: '앱이 유용하셨다면 제작자에게 응원을 보내주세요',
    cancel: '취소',
    ok: '확인',
    close: '닫기',
    homeSettingsTooltip: '기본 런처 설정',
    settings: '설정',
    language: '언어',
    unlock: '잠금 해제',
    lock: '잠금',
    clearHistory: '기록 삭제',
    delete: '삭제',
    systemAppCannotUninstall: '시스템 앱은 삭제할 수 없습니다',
    appInfo: '앱 정보',
    playStore: '스토어',
    deleteFailed: '삭제 실패',
    copied: '복사됨',
    copy: '복사',
    donationCoffee: '커피 한 잔',
    donationDrink: '음료 한 잔',
    donationMeal: '식사 한 끼',
    donationBig: '큰 후원',
    tutorialTitle: '기본 홈 앱으로 설정',
    tutorialBody: '위쪽 🏠 버튼을 누르면 SearchIt을 기본 홈 앱으로 설정할 수 있어요.\n\n'
        '사용하다 불편하면 같은 버튼을 눌러 언제든 원래 쓰던 런처로 되돌릴 수 있습니다.',
  );

  static const en = S(
    appList: 'Apps',
    sectionNewLock: 'New & Lock',
    sectionUsed: 'Used',
    sectionUnused: 'Unused',
    recentSearch: 'Recent & Search',
    searchHint: 'Search',
    enterSearchTerm: 'Enter a search term',
    noResults: 'No Results',
    donationThanks: 'Thank you for your support!',
    purchaseFailed: 'Purchase failed',
    loadingPurchase: 'Loading purchase service...',
    supportTitle: 'Support',
    supportShort: 'Support',
    supportBody: 'If you found this app useful, please support the developer',
    cancel: 'Cancel',
    ok: 'OK',
    close: 'Close',
    homeSettingsTooltip: 'Set as Default',
    settings: 'Settings',
    language: 'Language',
    unlock: 'Unlock',
    lock: 'Lock',
    clearHistory: 'Clear History',
    delete: 'Delete',
    systemAppCannotUninstall: 'System apps cannot be uninstalled',
    appInfo: 'App Info',
    playStore: 'Play Store',
    deleteFailed: 'Delete Failed',
    copied: 'Copied',
    copy: 'Copy',
    donationCoffee: 'Coffee',
    donationDrink: 'Drink',
    donationMeal: 'Meal',
    donationBig: 'Big Support',
    tutorialTitle: 'Set as your home app',
    tutorialBody: 'Tap the 🏠 button at the top to set SearchIt as your default home app.\n\n'
        'If it ever feels inconvenient, tap the same button anytime to switch back to your previous launcher.',
  );

  static S of(AppLang lang) => lang == AppLang.ko ? ko : en;
}
