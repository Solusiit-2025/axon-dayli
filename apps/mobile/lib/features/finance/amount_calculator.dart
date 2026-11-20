import 'package:flutter/material.dart';

import '../../core/money.dart';
import '../../core/theme.dart';

/// Membuka kalkulator nominal. Mengembalikan nilai akhir (rintisan) atau null
/// bila pengguna menutup tanpa memakai hasilnya.
Future<int?> showAmountCalculator(BuildContext context, {int initial = 0}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => AmountCalculatorSheet(initial: initial),
  );
}

/// Kalkulator sederhana untuk mengisi nominal transaksi.
///
/// Mendukung operasi berantai (+, -, *, /) seperti kalkulator ponsel:
/// setiap operator baru menyelesaikan operasi sebelumnya.
class AmountCalculatorSheet extends StatefulWidget {
  const AmountCalculatorSheet({super.key, this.initial = 0});

  final int initial;

  @override
  State<AmountCalculatorSheet> createState() => _AmountCalculatorSheetState();
}

class _AmountCalculatorSheetState extends State<AmountCalculatorSheet> {
  String _entry = '';
  double? _accumulator;
  String? _operator;
  bool _justEvaluated = false;
  String _error = '';

  final List<String> _history = [];

  @override
  void initState() {
    super.initState();
    if (widget.initial > 0) _entry = widget.initial.toString();
  }

  double get _currentValue => double.tryParse(_entry.isEmpty ? '0' : _entry) ?? 0;

  int get _resultValue =>
      (_accumulator == null && _entry.isEmpty ? 0 : (_accumulator ?? _currentValue))
          .round();

  String get _display {
    if (_entry.isNotEmpty) return formatNumber(int.tryParse(_entry) ?? 0);
    if (_accumulator != null) return formatNumber(_accumulator!.round());
    return '0';
  }

  void _inputDigit(String digit) {
    setState(() {
      _error = '';
      if (_justEvaluated) {
        _accumulator = null;
        _operator = null;
        _history.clear();
        _entry = '';
        _justEvaluated = false;
      }
      if (_entry == '0') _entry = '';
      if (_entry.length >= 12) return;
      _entry += digit;
    });
  }

  void _backspace() {
    setState(() {
      _error = '';
      if (_justEvaluated) {
        _justEvaluated = false;
      }
      if (_entry.isNotEmpty) _entry = _entry.substring(0, _entry.length - 1);
    });
  }

  void _clear() {
    setState(() {
      _entry = '';
      _accumulator = null;
      _operator = null;
      _history.clear();
      _justEvaluated = false;
      _error = '';
    });
  }

  void _applyOperator(String op) {
    setState(() {
      _error = '';
      _justEvaluated = false;

      if (_entry.isNotEmpty) {
        final value = _currentValue;
        if (_operator != null && _accumulator != null) {
          final next = _compute(_accumulator!, value, _operator!);
          if (next == null) {
            _error = 'Tidak bisa dibagi 0';
            return;
          }
          _accumulator = next;
        } else {
          _accumulator = value;
        }
        _history
          ..clear()
          ..add(formatNumber(_accumulator!.round()));
        _entry = '';
      }

      _operator = op;
    });
  }

  void _evaluate() {
    setState(() {
      _error = '';
      if (_operator == null || _accumulator == null) {
        _accumulator = _currentValue;
        _entry = '';
        _justEvaluated = true;
        return;
      }

      final right = _entry.isEmpty ? _accumulator! : _currentValue;
      final result = _compute(_accumulator!, right, _operator!);
      if (result == null) {
        _error = 'Tidak bisa dibagi 0';
        return;
      }
      _history
        ..clear()
        ..add('${formatNumber(_accumulator!.round())} $_operator ${formatNumber(right.round())}');
      _accumulator = result;
      _entry = '';
      _operator = null;
      _justEvaluated = true;
    });
  }

  double? _compute(double left, double right, String op) {
    switch (op) {
      case '+':
        return left + right;
      case '-':
        return left - right;
      case '*':
        return left * right;
      case '/':
        if (right == 0) return null;
        return left / right;
      default:
        return right;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Layar hasil
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _history.isEmpty ? 'Hitung nominal' : _history.join(' '),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        'Rp',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: accent),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          _display,
                          textAlign: TextAlign.right,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_error.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(_error, style: TextStyle(fontSize: 12, color: kDanger)),
                  ],
                ],
              ),
            ),

            // Tombol
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                children: [
                  _row([_key('7'), _key('8'), _key('9'), _op('/')]),
                  _row([_key('4'), _key('5'), _key('6'), _op('*')]),
                  _row([_key('1'), _key('2'), _key('3'), _op('-')]),
                  _row([_key('0'), _key('000'), _iconKey(Icons.backspace_outlined, _backspace), _op('+')]),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: OutlinedButton(
                      onPressed: _clear,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 46),
                        foregroundColor: kDanger,
                        side: BorderSide(color: kDanger.withValues(alpha: 0.4)),
                      ),
                      child: const Text('Hapus', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: FilledButton.tonal(
                      onPressed: _evaluate,
                      style: FilledButton.styleFrom(minimumSize: const Size(0, 46)),
                      child: const Text('=', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(_resultValue),
                      style: FilledButton.styleFrom(minimumSize: const Size(0, 46)),
                      child: const Text('Gunakan'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: children[i]),
          ],
        ],
      ),
    );
  }

  Widget _key(String digit) {
    return SizedBox(
      height: 52,
      child: FilledButton.tonal(
        onPressed: () => _inputDigit(digit),
        style: FilledButton.styleFrom(
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Text(
          digit,
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Widget _op(String symbol) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 52,
      child: FilledButton(
        onPressed: () => _applyOperator(symbol),
        style: FilledButton.styleFrom(
          padding: EdgeInsets.zero,
          backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
          foregroundColor: theme.colorScheme.primary,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Text(
          symbol,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  Widget _iconKey(IconData icon, VoidCallback onTap) {
    return SizedBox(
      height: 52,
      child: FilledButton.tonal(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Icon(icon, size: 20),
      ),
    );
  }
}
