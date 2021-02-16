import 'dart:async';
import 'dart:html' as html;

Future<String> openIframe(String url, String name) async {
  final child = html.IFrameElement();
  child.name = name;
  child.src = url;
  child.height = '10';
  child.width = '10';
  child.style.border = 'none';
  child.style.display = 'none';

  html.querySelector("body").children.add(child);

  final completer = Completer<String>();

  html.window.onMessage.first.then((event) {
    final url = event.data.toString();
    print(url);
    completer.complete(url);
    html.querySelector("body").children.remove(child);
  });

  return completer.future;
}

String getFullUrl() {
  return html.window.location.href;
}

void redirectTo(String url) {
  html.window.location.assign(url);
}
