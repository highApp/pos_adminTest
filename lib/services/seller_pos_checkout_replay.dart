import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/due_payment.dart';
import 'seller_service.dart';

/// Result of applying queued seller-side POS effects after the sale doc exists on Firestore.
enum SellerPostSaleReplayOutcome {
  /// Wrote history / dues / credit and patched the sale.
  applied,

  /// Sale already had [SellerPosCheckoutReplay.saleSideEffectsField]; nothing to do.
  skippedAlreadySynced,

  /// `sales/{saleId}` not on server yet — keep queue row and retry later.
  saleDocumentMissing,
}

/// Replays the same Firestore work as an online POS checkout with a selected seller.
///
/// Offline POS embeds replay input under [queuedSaleMetaKey] on the **queued** sale JSON only.
/// That key is removed before writing `sales/{id}` to Firestore.
abstract final class SellerPosCheckoutReplay {
  static const String saleSideEffectsField = 'sellerSideEffectsSynced';

  /// SQLite queue / local sale JSON only — never sent to Firestore.
  static const String queuedSaleMetaKey = '_queueOnly';

  static Map<String, dynamic> stripQueuedMetadataForFirestore(Map<String, dynamic> map) {
    final out = Map<String, dynamic>.from(map);
    out.remove(queuedSaleMetaKey);
    return out;
  }

  static Map<String, dynamic>? decodeSellerReplayFromQueuedSale(Map<String, dynamic> map) {
    final meta = map[queuedSaleMetaKey];
    if (meta is! Map) return null;
    final inner = meta['sellerReplay'];
    if (inner is! Map) return null;
    return Map<String, dynamic>.from(inner as Map<dynamic, dynamic>);
  }

  static Future<SellerPostSaleReplayOutcome> replayFromQueuePayload({
    required FirebaseFirestore firestore,
    required String saleId,
    required Map<String, dynamic> payload,
  }) async {
    final saleRef = firestore.collection('sales').doc(saleId);
    final saleSnap = await saleRef.get();
    if (!saleSnap.exists || saleSnap.data() == null) {
      debugPrint('seller_post_sale: sale $saleId not on server yet — will retry');
      return SellerPostSaleReplayOutcome.saleDocumentMissing;
    }
    final existing = saleSnap.data()!;
    if (existing[saleSideEffectsField] == true) {
      return SellerPostSaleReplayOutcome.skippedAlreadySynced;
    }

    final sellerId = payload['sellerId'] as String?;
    if (sellerId == null || sellerId.isEmpty) {
      debugPrint('seller_post_sale: missing sellerId');
      await saleRef.set({saleSideEffectsField: true}, SetOptions(merge: true));
      return SellerPostSaleReplayOutcome.applied;
    }

    final amountPaid = (payload['amountPaid'] as num?)?.toDouble() ?? 0.0;
    final cartTotal = (payload['cartTotal'] as num?)?.toDouble() ?? 0.0;
    final existingDueTotal =
        (payload['existingDueTotal'] as num?)?.toDouble() ?? 0.0;
    final description = payload['description'] as String? ?? '';
    final saleDateStr = payload['saleDate'] as String?;
    final saleDate = saleDateStr != null
        ? DateTime.tryParse(saleDateStr) ?? DateTime.now()
        : DateTime.now();

    final sellerService = SellerService();

    double creditBalance = await sellerService.getCreditBalance(sellerId);
    double creditUsed = 0.0;
    double remainingSaleAmount = cartTotal;

    if (creditBalance > 0 && remainingSaleAmount > 0) {
      creditUsed =
          await sellerService.useCreditBalance(sellerId, remainingSaleAmount);
      remainingSaleAmount -= creditUsed;
    }

    final cashForCurrentSale = remainingSaleAmount > 0 && amountPaid > 0
        ? (amountPaid < remainingSaleAmount ? amountPaid : remainingSaleAmount)
        : 0.0;
    final cashForExistingDues =
        amountPaid > cashForCurrentSale ? amountPaid - cashForCurrentSale : 0.0;
    final totalAmountForCurrentSale = creditUsed + cashForCurrentSale;

    double actualRecoveryBalance = 0.0;
    double actualChange = 0.0;

    if (cashForExistingDues > 0 && existingDueTotal > 0) {
      // Must succeed before addSellerHistory — same rule as online POS checkout.
      final remainingAfterDues = await sellerService
          .applyPaymentToDuePayments(
        sellerId,
        cashForExistingDues,
        prioritizeBillsWithSaleDateSameDayAs: saleDate,
      );
      actualRecoveryBalance = cashForExistingDues - remainingAfterDues;
      if (remainingAfterDues > 0) {
        actualChange = remainingAfterDues;
      }
    } else {
      if (amountPaid > cashForCurrentSale) {
        actualChange = amountPaid - cashForCurrentSale;
      }
    }

    try {
      await sellerService.addSellerHistory(
        sellerId: sellerId,
        saleId: saleId,
        saleAmount: cartTotal,
        amountPaid: totalAmountForCurrentSale,
        saleDate: saleDate,
        description: description.isEmpty ? null : description,
      );
    } catch (e) {
      debugPrint('seller_post_sale: addSellerHistory: $e');
      rethrow;
    }

    if (totalAmountForCurrentSale < cartTotal) {
      final dueAmount = cartTotal - totalAmountForCurrentSale;
      try {
        final duePayment = DuePayment(
          id: const Uuid().v4(),
          sellerId: sellerId,
          saleId: saleId,
          totalAmount: cartTotal,
          amountPaid: totalAmountForCurrentSale,
          dueAmount: dueAmount,
          createdAt: saleDate,
          isPaid: false,
        );
        await sellerService.addDuePayment(duePayment);
      } catch (e) {
        debugPrint('seller_post_sale: addDuePayment: $e');
        rethrow;
      }
    }

    final now = DateTime.now().toUtc().toIso8601String();
    await saleRef.set(
      {
        'recoveryBalance': actualRecoveryBalance,
        'change': actualChange,
        'creditUsed': creditUsed,
        saleSideEffectsField: true,
        'updatedAt': now,
      },
      SetOptions(merge: true),
    );

    return SellerPostSaleReplayOutcome.applied;
  }
}
