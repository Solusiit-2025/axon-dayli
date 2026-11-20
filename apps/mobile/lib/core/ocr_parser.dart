class OcrResult {
  const OcrResult({
    this.amount,
    this.payee,
    this.date,
    required this.rawText,
  });

  final int? amount;
  final String? payee;
  final DateTime? date;
  final String rawText;
}

class OcrParser {
  static OcrResult parse(String rawText) {
    if (rawText.trim().isEmpty) {
      return OcrResult(rawText: rawText);
    }

    final lines = rawText
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    int? detectedAmount = _extractAmount(lines);
    String? detectedPayee = _extractPayee(lines);
    DateTime? detectedDate = _extractDate(rawText);

    return OcrResult(
      amount: detectedAmount,
      payee: detectedPayee,
      date: detectedDate,
      rawText: rawText,
    );
  }

  static int? _extractAmount(List<String> lines) {
    final keywords = [
      'grand total',
      'total bayar',
      'total akhir',
      'total',
      'subtotal',
      'sub total',
      'jumlah bayar',
      'jumlah',
      'bayar',
      'cash',
      'tunai',
      'harga',
    ];

    // Priority 1: Match keyword line or line immediately following keyword line
    for (var i = 0; i < lines.length; i++) {
      final lineLower = lines[i].toLowerCase();
      for (final kw in keywords) {
        if (lineLower.contains(kw)) {
          // Check numbers in current line
          final valCurrent = _findNumbersInLine(lines[i]);
          if (valCurrent != null && valCurrent > 0) return valCurrent;

          // Check next line
          if (i + 1 < lines.length) {
            final valNext = _findNumbersInLine(lines[i + 1]);
            if (valNext != null && valNext > 0) return valNext;
          }
        }
      }
    }

    // Priority 2: Find all numbers and return the max valid transaction amount
    final allNumbers = <int>[];
    for (final line in lines) {
      final nums = _findAllNumbersInLine(line);
      allNumbers.addAll(nums);
    }

    // Filter out numbers that look like dates or phone numbers (> 10,000,000,000 or < 100)
    final validNumbers = allNumbers.where((n) => n >= 500 && n <= 500000000).toList();
    if (validNumbers.isNotEmpty) {
      validNumbers.sort();
      return validNumbers.last; // Usually the total is the largest number on the receipt
    }

    return null;
  }

  static int? _findNumbersInLine(String line) {
    final nums = _findAllNumbersInLine(line);
    if (nums.isEmpty) return null;

    // Filter out obvious dates/years like 2024, 2025
    final filtered = nums.where((n) => n < 2020 || n > 2030).toList();
    if (filtered.isNotEmpty) return filtered.last;
    return nums.last;
  }

  static List<int> _findAllNumbersInLine(String line) {
    // Regex matches numbers with optional dot/comma separators e.g. 150.000 or 150,000 or 150000
    final regex = RegExp(r'(?:Rp\.?\s*)?(\d{1,3}(?:[.,]\d{3})*|\d+)');
    final matches = regex.allMatches(line);
    final results = <int>[];

    for (final match in matches) {
      var str = match.group(1);
      if (str == null) continue;
      // Remove thousand separators
      str = str.replaceAll('.', '').replaceAll(',', '');
      final parsed = int.tryParse(str);
      if (parsed != null && parsed > 0) {
        results.add(parsed);
      }
    }
    return results;
  }

  static String? _extractPayee(List<String> lines) {
    final skipWords = [
      'selamat datang',
      'welcome',
      'faktur',
      'receipt',
      'nota',
      'bukti',
      'kwitansi',
      'kasir',
      'pos',
      'order',
    ];

    for (final line in lines.take(5)) {
      final lower = line.toLowerCase();
      if (skipWords.any((w) => lower.contains(w))) continue;
      // Clean special characters
      final cleaned = line.replaceAll(RegExp(r'[^\w\s&.-]'), '').trim();
      if (cleaned.length >= 3 && !RegExp(r'^\d+$').hasMatch(cleaned)) {
        return cleaned;
      }
    }
    return null;
  }

  static DateTime? _extractDate(String text) {
    final regex = RegExp(r'(\d{1,2})[/.-](\d{1,2})[/.-](\d{2,4})');
    final match = regex.firstMatch(text);
    if (match != null) {
      final d = int.tryParse(match.group(1) ?? '');
      final m = int.tryParse(match.group(2) ?? '');
      var y = int.tryParse(match.group(3) ?? '');
      if (d != null && m != null && y != null) {
        if (y < 100) y += 2000;
        if (m >= 1 && m <= 12 && d >= 1 && d <= 31) {
          try {
            return DateTime(y, m, d);
          } catch (_) {}
        }
      }
    }
    return null;
  }
}
