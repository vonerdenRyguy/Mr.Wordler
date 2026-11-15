import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Reports a fixed "natural" height to any parent that asks how tall its
/// child would like to be, and otherwise lays the child out to fill
/// whatever space it is given.
///
/// Home uses it for the village picture: the page measures itself to
/// decide whether it must scroll, the picture counts as [height] in that
/// sum, and it then stretches into any room left over. (The picture's own
/// widgets can't be measured that way, so the question stops here.)
class MinHeightBox extends SingleChildRenderObjectWidget {
  const MinHeightBox({super.key, required this.height, super.child});

  final double height;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderMinHeightBox(height);

  @override
  void updateRenderObject(BuildContext context, covariant RenderObject renderObject) {
    (renderObject as _RenderMinHeightBox).naturalHeight = height;
  }
}

class _RenderMinHeightBox extends RenderProxyBox {
  _RenderMinHeightBox(this._naturalHeight);

  double _naturalHeight;
  set naturalHeight(double value) {
    if (value == _naturalHeight) return;
    _naturalHeight = value;
    markNeedsLayout();
  }

  @override
  double computeMinIntrinsicHeight(double width) => _naturalHeight;

  @override
  double computeMaxIntrinsicHeight(double width) => _naturalHeight;

  @override
  double computeMinIntrinsicWidth(double height) => 0;

  @override
  double computeMaxIntrinsicWidth(double height) => 0;

  @override
  void performLayout() {
    final height = constraints.hasBoundedHeight ? constraints.maxHeight : _naturalHeight;
    final box = BoxConstraints.tightFor(
      width: constraints.hasBoundedWidth ? constraints.maxWidth : constraints.minWidth,
      height: height < _naturalHeight ? _naturalHeight : height,
    );
    child?.layout(box);
    size = constraints.constrain(box.biggest);
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) => constraints.constrain(Size(
        constraints.hasBoundedWidth ? constraints.maxWidth : constraints.minWidth,
        constraints.hasBoundedHeight ? constraints.maxHeight : _naturalHeight,
      ));
}
