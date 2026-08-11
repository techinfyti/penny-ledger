import 'dart:async';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'premium_service.dart';

const String lifetimeProductId = 'pennyledger_premium_lifetime';
const String monthlyProductId = 'pennyledger_premium_monthly_v2';
const String fiveYearProductId = 'pennyledger_premium_5year';

class PurchaseService {
  final InAppPurchase _iap = InAppPurchase.instance;
  final PremiumService _premiumService;
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  String? _uid;

  PurchaseService(this._premiumService);

  void init(String uid) {
    _uid = uid;
    _subscription ??= _iap.purchaseStream.listen(_onPurchaseUpdate, onError: (_) {});
  }

  Future<List<ProductDetails>> queryProducts() async {
    final available = await _iap.isAvailable();
    if (!available) return [];
    final response = await _iap.queryProductDetails({lifetimeProductId, monthlyProductId, fiveYearProductId});
    return response.productDetails;
  }

  Future<void> buy(ProductDetails product) {
    final param = PurchaseParam(productDetails: product);
    return _iap.buyNonConsumable(purchaseParam: param);
  }

  /// Re-delivers the user's past purchases through the purchase stream —
  /// needed after a reinstall, or a sign-in on a new device, since Play
  /// Billing entitlements live on the user's Google account, not on-device.
  Future<void> restore() => _iap.restorePurchases();

  void _onPurchaseUpdate(List<PurchaseDetails> purchases) {
    for (final purchase in purchases) {
      if (purchase.status == PurchaseStatus.purchased || purchase.status == PurchaseStatus.restored) {
        final String plan;
        DateTime? expiresAt;
        final now = DateTime.now();
        if (purchase.productID == monthlyProductId) {
          plan = 'monthly';
          // Extends on every delivery of this event, including renewals, so
          // a subscription that keeps auto-renewing keeps pushing its expiry
          // forward. If it lapses, no further events arrive and this date
          // simply stops advancing until it's in the past.
          expiresAt = DateTime(now.year, now.month + 1, now.day);
        } else if (purchase.productID == fiveYearProductId) {
          plan = 'five_year';
          expiresAt = DateTime(now.year + 5, now.month, now.day);
        } else {
          plan = 'lifetime';
          expiresAt = null;
        }
        final uid = _uid;
        if (uid != null) {
          _premiumService.setPremium(uid, true, plan: plan, expiresAt: expiresAt);
        }
      }
      if (purchase.pendingCompletePurchase) {
        _iap.completePurchase(purchase);
      }
    }
  }
}
