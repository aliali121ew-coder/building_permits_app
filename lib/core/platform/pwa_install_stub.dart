bool pwaCanInstall() => false;
bool pwaIsStandalone() => true;
bool pwaIsIOS() => false;
Future<String> pwaInstall() async => 'unavailable';
void onPwaEvent(String name, void Function() callback) {}
