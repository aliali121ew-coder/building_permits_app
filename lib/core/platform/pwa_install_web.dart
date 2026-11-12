import 'dart:js_interop';

import 'package:web/web.dart' as web;

// الدوال معرّفة في web/index.html
@JS('pwaCanInstall')
external JSBoolean _canInstall();

@JS('pwaIsStandalone')
external JSBoolean _isStandalone();

@JS('pwaIsIOS')
external JSBoolean _isIOS();

@JS('pwaInstall')
external JSPromise<JSString> _install();

bool pwaCanInstall() => _canInstall().toDart;
bool pwaIsStandalone() => _isStandalone().toDart;
bool pwaIsIOS() => _isIOS().toDart;

/// يعرض نافذة التثبيت؛ النتيجة: accepted / dismissed / unavailable
Future<String> pwaInstall() async => (await _install().toDart).toDart;

void onPwaEvent(String name, void Function() callback) =>
    web.window.addEventListener(name, ((web.Event _) => callback()).toJS);
