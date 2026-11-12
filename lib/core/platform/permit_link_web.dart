import 'dart:js_interop';

// معرّفة في web/index.html: تُرجع رابط الإجازة الذي فُتح به التطبيق مرة واحدة فقط
@JS('takePermitLink')
external JSString _take();

String? takePendingPermitLink() {
  final v = _take().toDart;
  return v.isEmpty ? null : v;
}
