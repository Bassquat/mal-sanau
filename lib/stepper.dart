import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Asks for a whole number. Returns null when cancelled.
Future<int?> askNumber(BuildContext context, int initial, {String? title}) {
  final c = TextEditingController(text: '$initial');
  c.selection = TextSelection(baseOffset: 0, extentOffset: c.text.length);
  return showDialog<int>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title ?? 'Санды жазыңыз'),
      content: TextField(
        controller: c,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onSubmitted: (v) => Navigator.pop(ctx, int.tryParse(v)),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Болдырмау')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, int.tryParse(c.text)),
            child: const Text('Сақтау')),
      ],
    ),
  );
}

/// How much one auto-repeat tick adds after [ticks] ticks of holding the
/// button: slow first, then faster.
int stepForTick(int ticks) {
  if (ticks < 6) return 1;
  if (ticks < 14) return 5;
  if (ticks < 28) return 10;
  if (ticks < 45) return 50;
  return 100;
}

/// Plus/minus button: a tap changes by 1, holding it repeats and speeds up.
class HoldButton extends StatefulWidget {
  const HoldButton({
    super.key,
    required this.icon,
    required this.sign,
    required this.onStep,
    this.filled = false,
  });

  final IconData icon;
  final int sign; // +1 or -1
  final ValueChanged<int> onStep; // receives a signed delta
  final bool filled;

  @override
  State<HoldButton> createState() => _HoldButtonState();
}

class _HoldButtonState extends State<HoldButton> {
  Timer? _timer;
  int _ticks = 0;

  void _start() {
    _ticks = 0;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 120), (_) {
      _ticks++;
      widget.onStep(widget.sign * stepForTick(_ticks));
    });
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => widget.onStep(widget.sign),
      onLongPressStart: (_) => _start(),
      onLongPressEnd: (_) => _stop(),
      onLongPressCancel: _stop,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.filled ? cs.primary : null,
          border: widget.filled ? null : Border.all(color: cs.outline),
        ),
        child: Icon(widget.icon,
            color: widget.filled ? cs.onPrimary : cs.onSurface),
      ),
    );
  }
}

/// − [number] + control. Tap the number to type it, hold ± to count fast.
class CountStepper extends StatelessWidget {
  const CountStepper({super.key, required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  void _delta(int d) => onChanged((value + d) < 0 ? 0 : value + d);

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          HoldButton(icon: Icons.remove, sign: -1, onStep: _delta),
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () async {
              final n = await askNumber(context, value);
              if (n != null) onChanged(n);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Text('$value',
                  style: Theme.of(context).textTheme.headlineSmall),
            ),
          ),
          HoldButton(icon: Icons.add, sign: 1, filled: true, onStep: _delta),
        ],
      );
}
