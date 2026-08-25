import 'package:flutter/foundation.dart';

class AppState {
  static final ValueNotifier<String?> selectedMallId = ValueNotifier<String?>(null);
  static final ValueNotifier<String?> selectedMallName = ValueNotifier<String?>(null);
}