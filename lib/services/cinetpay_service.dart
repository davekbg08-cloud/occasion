import 'package:cinetpay/cinetpay.dart';
import 'package:flutter/material.dart';
import 'package:injectable/injectable.dart';

import 'phone_number_validator.dart';

@injectable
class CinetPayService {
  static const String _siteId = 'TON_SITE_ID';
  static const String _apiKey = 'TA_CLE_API';
  static const String _notifyUrl = 'https://example.com/cinetpay/notify';
  static const String _currency = 'XOF';

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
              'apikey': _apiKey,
              'site_id': int.tryParse(_siteId) ?? _siteId,
              'notify_url': _notifyUrl,
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
