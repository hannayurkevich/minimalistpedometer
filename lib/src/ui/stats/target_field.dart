import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../data/step_store.dart';
import '../../theme/palette.dart';
import '../../util/format.dart';

/// The Daily target figure. Tap it to edit the number in place (number
/// keyboard); tapping elsewhere, Done, or swiping away saves it. Values are
/// clamped to [StepStore.minTarget]…[StepStore.maxTarget]; an empty entry
/// keeps the previous target. No extra buttons or dialogs.
class TargetField extends StatefulWidget {
  const TargetField({
    super.key,
    required this.target,
    required this.style,
    required this.onChanged,
  });

  final int target;
  final TextStyle style;
  final ValueChanged<int> onChanged;

  @override
  State<TargetField> createState() => _TargetFieldState();
}

class _TargetFieldState extends State<TargetField> {
  final _text = TextEditingController();
  final _focus = FocusNode(debugLabel: 'daily target');
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus && _editing) _commit();
    });
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _startEditing() {
    final digits = '${widget.target}';
    _text.value = TextEditingValue(
      text: digits,
      selection: TextSelection(baseOffset: 0, extentOffset: digits.length),
    );
    setState(() => _editing = true);
    _focus.requestFocus();
  }

  void _commit() {
    final value = int.tryParse(_text.text);
    setState(() => _editing = false);
    if (_focus.hasFocus) _focus.unfocus();
    if (value != null) widget.onChanged(StepStore.clampTarget(value));
  }

  @override
  Widget build(BuildContext context) {
    if (!_editing) {
      return Semantics(
        button: true,
        label: 'Daily target ${widget.target} steps. Double tap to change',
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _startEditing,
          child: Text(
            formatSteps(widget.target),
            maxLines: 1,
            style: widget.style,
          ),
        ),
      );
    }
    return EditableText(
      controller: _text,
      focusNode: _focus,
      style: widget.style,
      textAlign: TextAlign.center,
      cursorColor: Palette.accentYellow,
      backgroundCursorColor: Palette.mutedBeige,
      selectionColor: Palette.accentYellow.withValues(alpha: 0.35),
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.done,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter('${StepStore.maxTarget}'.length),
      ],
      maxLines: 1,
      autocorrect: false,
      enableSuggestions: false,
      onSubmitted: (_) => _commit(),
      onTapOutside: (_) => _commit(),
    );
  }
}
