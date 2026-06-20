import 'package:get_it/get_it.dart';

import 'chat_service.dart';
import 'cinetpay_service.dart';
import 'mobile_money_service.dart';
import 'status_service.dart';

final getIt = GetIt.instance;

void configureServices() {
  if (!getIt.isRegistered<MobileMoneyService>()) {
    getIt.registerLazySingleton<MobileMoneyService>(MobileMoneyService.new);
  }

  if (!getIt.isRegistered<CinetPayService>()) {
    getIt.registerLazySingleton<CinetPayService>(CinetPayService.new);
  }

  if (!getIt.isRegistered<ChatService>()) {
    getIt.registerLazySingleton<ChatService>(ChatService.new);
  }

  if (!getIt.isRegistered<StatusService>()) {
    getIt.registerLazySingleton<StatusService>(StatusService.new);
  }
}
