import 'package:cinetpay/cinetpay.dart';
import 'package:flutter/material.dart';
import 'package:injectable/injectable.dart';

import 'payment_config.dart';
import 'phone_number_validator.dart';

@injectable
class CinetPayService {
  static const String _currency = 'CDF';

  Future<bool> initiatePayment({
    required BuildContext context,
    required double amount,
    required String transactionId,
    required String description,
    required String customerPhone,
    String customerName = 'Client',
    String customerEmail = 'client@app.com',
    String channels = 'MOBILE_MONEY',
    ValueChanged<Map<String, dynamic>>? onSuccess,
    ValueChanged<Map<String, dynamic>>? onError,
  }) async {
    if (!PaymentConfig.isConfigured) {
      throw StateError(
        "Le paiement CinetPay n'est pas encore configuré. "
        'Renseigne CINETPAY_APIKEY et CINETPAY_SITE_ID (lib/services/payment_config.dart).',
      );
    }

    if (amount < 100) {
      throw ArgumentError('Le montant CinetPay doit être au moins 100 FCFA');
    }

    final phoneValidation = PhoneNumberValidator.validate(customerPhone);
    if (!phoneValidation.isValid) {
      throw ArgumentError(phoneValidation.message);
    }

    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (checkoutContext) {
          var hasReturned = false;

          void closeCheckout(bool value) {
            if (hasReturned) return;
            hasReturned = true;

            if (checkoutContext.mounted &&
                Navigator.of(checkoutContext).canPop()) {
              Navigator.of(checkoutContext).pop(value);
            }
          }

          return CinetPayCheckout(
            title: 'Paiement CinetPay',
            titleBackgroundColor: Colors.green,
            titleStyle: const TextStyle(color: Colors.white),
            configData: <String, dynamic>{
              'apikey': PaymentConfig.cinetpayApiKey,
              'site_id':
                  int.tryParse(PaymentConfig.cinetpaySiteId) ??
                  PaymentConfig.cinetpaySiteId,
              'notify_url': PaymentConfig.cinetpayNotifyUrl,
            },
            paymentData: <String, dynamic>{
              'transaction_id': transactionId,
              'amount': amount.round(),
              'currency': _currency,
              'channels': channels,
              'description': description,
              'customer_name': customerName,
              'customer_email': customerEmail,
              'customer_phone_number': phoneValidation.normalized,
            },
            waitResponse: (response) {
              final isSuccess = _isSuccessfulResponse(response);
              if (isSuccess) {
                onSuccess?.call(response);
              } else {
                onError?.call(response);
              }
              closeCheckout(isSuccess);
            },
            onError: (error) {
              onError?.call(error);
              closeCheckout(false);
            },
          );
        },
      ),
    );

    return result ?? false;
  }

  bool _isSuccessfulResponse(Map<String, dynamic> response) {
    final status = response['status']?.toString().toUpperCase();
    final code = response['code']?.toString();

    return status == 'ACCEPTED' || status == 'SUCCESS' || code == '201';
  }
}
