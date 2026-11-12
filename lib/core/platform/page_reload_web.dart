import 'package:web/web.dart' as web;

void reloadPage() => web.window.location.reload();

void openInNewTab(String url) => web.window.open(url, '_blank');
