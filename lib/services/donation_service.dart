import 'dart:async';

import 'package:in_app_purchase/in_app_purchase.dart';

import '../l10n/strings.dart';

class DonationService {
  DonationService._();

  static const productIds = [
    'donation_coffee',
    'donation_drink',
    'donation_meal',
    'donation_big',
  ];

  static String labelFor(String productId) {
    switch (productId) {
      case 'donation_coffee':
        return tr.donationCoffee;
      case 'donation_drink':
        return tr.donationDrink;
      case 'donation_meal':
        return tr.donationMeal;
      case 'donation_big':
        return tr.donationBig;
      default:
        return productId;
    }
  }

  static final _iap = InAppPurchase.instance;
  static StreamSubscription<List<PurchaseDetails>>? _sub;
  static List<ProductDetails> _products = [];
  static void Function(bool success)? _onResult;

  static List<ProductDetails> get products => List.unmodifiable(_products);

  static Future<void> init() async {
    if (!await _iap.isAvailable()) return;

    _sub = _iap.purchaseStream.listen(
      _handlePurchases,
      onDone: () => _sub?.cancel(),
      onError: (_) {},
    );

    final response = await _iap.queryProductDetails(productIds.toSet());
    final byId = {for (final p in response.productDetails) p.id: p};
    _products = productIds
        .map((id) => byId[id])
        .whereType<ProductDetails>()
        .toList();
  }

  static Future<void> buy(ProductDetails product) =>
      _iap.buyConsumable(purchaseParam: PurchaseParam(productDetails: product));

  static void setOnResult(void Function(bool success)? cb) => _onResult = cb;

  static void _handlePurchases(List<PurchaseDetails> purchases) {
    for (final p in purchases) {
      if (p.status == PurchaseStatus.purchased) {
        _iap.completePurchase(p);
        _onResult?.call(true);
      } else if (p.status == PurchaseStatus.error) {
        _onResult?.call(false);
      }
    }
  }

  static void dispose() {
    _sub?.cancel();
    _sub = null;
  }
}
