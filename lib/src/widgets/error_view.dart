import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Writes [error] to the device log, where `adb logcat` can find it.
void reportError(Object error, StackTrace? stack, String doing) {
  debugPrint('ToolPDF View error while $doing: $error');
  if (stack != null) debugPrint(stack.toString());
}

/// Makes failures visible and survivable.
///
/// Flutter's release-mode answer to a widget that fails to build is a solid
/// grey box the size of whatever failed - if that is the PDF viewer, the user
/// is left staring at a grey screen. This replaces the box with a short
/// message on a transparent background, so everything around the failure
/// stays visible and usable, and sends the details to the device log.
void installErrorHandling() {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    reportError(
      details.exception,
      details.stack,
      details.context?.toDescription() ?? 'running',
    );
    if (kDebugMode) previous?.call(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    reportError(error, stack, 'running a background task');
    return true;
  };
  ErrorWidget.builder = (details) => const FriendlyErrorBox();
}

/// What is shown in place of a widget that failed to build.
///
/// It can stand in for anything, so it relies on nothing: no theme, no
/// localizations, no text direction from its ancestors.
class FriendlyErrorBox extends StatelessWidget {
  const FriendlyErrorBox({super.key});

  static const _messages = <String, String>{
    'en': 'Something went wrong here',
    'pt': 'Algo correu mal aqui',
    'es': 'Algo salió mal aquí',
    'fr': 'Un problème est survenu ici',
    'ru': 'Здесь что-то пошло не так',
  };

  @override
  Widget build(BuildContext context) {
    final language = PlatformDispatcher.instance.locale.languageCode;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: Color(0xF2323232),
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Text(
              _messages[language] ?? _messages['en']!,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFFFFFFF),
                fontSize: 14,
                height: 1.3,
                decoration: TextDecoration.none,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
