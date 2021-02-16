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

Future<void> openPopUp(
    String url, String name, int width, int height, bool center,
    {String additionalOptions}) async {
  var options =
      'width=$width,height=$height,toolbar=no,location=no,directories=no,status=no,menubar=no,copyhistory=no';
  if (center) {
    final top = (html.window.outerHeight - height) / 2 +
        html.window.screen.available.top;
    final left = (html.window.outerWidth - width) / 2 +
        html.window.screen.available.left;

    options += 'top=$top,left=$left';
  }

  if (additionalOptions != null && additionalOptions != '')
    options += ',$additionalOptions';

  final child = html.window.open(url, name, options);
  final c = new Completer();

  while (!c.isCompleted) {
    await Future.delayed(Duration(milliseconds: 500));
    if (child.closed) c.complete();
  }
  return;
}

void closeCurrentPopUp() => html.window.close();
