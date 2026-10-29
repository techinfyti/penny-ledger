/// One word of a PDF text line with where it sits on the page, so table
/// columns can be told apart. Spaces between words come through as their own
/// whitespace-only words.
class PdfWord {
  final String text;
  final double x;
  final double width;

  const PdfWord(this.text, this.x, [this.width = 0]);

  double get center => x + width / 2;
}

class PdfLine {
  final String text;
  final List<PdfWord> words;

  const PdfLine(this.text, this.words);
}
