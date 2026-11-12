import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'documents_channel.dart';

/// Whether the app may read the PDFs in shared storage, kept up to date.
///
/// The answer always comes from Android itself. It is re-read every time the
/// app returns to the foreground, because on Android 11 and later the user
/// grants "All files access" on a system settings page, outside the app.
class StorageAccess extends ChangeNotifier with WidgetsBindingObserver {
  bool? _granted;
  bool _needsSettingsPage = false;
  bool _observing = false;

  /// False until Android has answered for the first time.
  bool get isKnown => _granted != null;

  bool get isGranted => _granted ?? false;

  /// True when granting means flipping a switch on a system settings page
  /// (Android 11+) rather than answering a permission dialog.
  bool get needsSettingsPage => _needsSettingsPage;

  Future<void> init() async {
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    try {
      _needsSettingsPage = await DocumentsChannel.storageNeedsSettingsPage();
    } on MissingPluginException {
      _needsSettingsPage = false;
    } on PlatformException {
      _needsSettingsPage = false;
    }
    await refresh();
  }

  /// Asks Android again and notifies listeners when the answer changed.
  Future<void> refresh() async {
    bool granted;
    try {
      granted = await DocumentsChannel.hasStorageAccess();
    } on MissingPluginException {
      // Not running on Android (tests, desktop): files are simply readable.
      granted = true;
    } on PlatformException {
      granted = false;
    }
    if (granted != _granted) {
      _granted = granted;
      notifyListeners();
    }
  }

  /// Shows the system permission dialog or settings page.
  ///
  /// The returned value is what Android reports once the user is back. Even
  /// if that report is lost (the activity can be recreated while the settings
  /// page is open), [didChangeAppLifecycleState] picks the change up.
  Future<bool> request() async {
    try {
      await DocumentsChannel.requestStorageAccess();
    } on MissingPluginException {
      // Nothing to ask for outside Android.
    } on PlatformException {
      // Fall through to whatever Android reports now.
    }
    await refresh();
    return isGranted;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }

  @visibleForTesting
  void debugSet({required bool granted, bool needsSettingsPage = false}) {
    _granted = granted;
    _needsSettingsPage = needsSettingsPage;
    notifyListeners();
  }
}

/// Single shared instance; initialised once in `main()`.
final StorageAccess storageAccess = StorageAccess();
