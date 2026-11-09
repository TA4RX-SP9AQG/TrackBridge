import 'package:flutter/widgets.dart';

/// Marks every mounted element dirty so all `t(...)` texts are looked up again (used when the
/// interface language changes). State and navigation are kept.
void rebuildEverything() {
  void mark(Element element) {
    element.markNeedsBuild();
    element.visitChildren(mark);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(mark);
}
