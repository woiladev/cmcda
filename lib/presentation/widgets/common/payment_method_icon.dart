import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';

/// Returns a widget for the given payment method.
/// For MTN MoMo and Orange Money, renders the brand logo image.
/// For other methods (cash, bank transfer), renders a Material icon with [color].
Widget paymentMethodIcon(
  String method, {
  double size = 24,
  Color? color,
}) {
  switch (method) {
    case AppConstants.paymentMtnMomo:
      return Image.asset(
        'assets/images/mtn mobile money.jpg',
        width: size,
        height: size,
        fit: BoxFit.contain,
      );
    case AppConstants.paymentOrangeMoney:
      return Image.asset(
        'assets/images/orange mobile money.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
      );
    case AppConstants.paymentBankTransfer:
      return Icon(Icons.account_balance_rounded, size: size, color: color);
    default:
      return Icon(Icons.payments_rounded, size: size, color: color);
  }
}
