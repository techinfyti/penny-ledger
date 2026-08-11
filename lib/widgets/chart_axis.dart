import 'dart:math' as math;

/// A clean, evenly-divided Y-axis range for fl_chart bar/line charts.
///
/// fl_chart doesn't round [maxY] to a "nice" number on its own, so an
/// arbitrary value like `maxDayTotal * 1.2` can land its top axis label
/// right next to the last auto-generated interval tick (e.g. both "30K"
/// and "31K" rendered almost on top of each other). Rounding both maxY
/// and the tick interval up to a clean multiple avoids that collision.
class ChartAxis {
  final double maxY;
  final double interval;

  const ChartAxis(this.maxY, this.interval);
}

ChartAxis niceYAxis(double rawMax) {
  if (rawMax <= 0) return const ChartAxis(100, 20);
  final magnitude = math.pow(10, (math.log(rawMax) / math.ln10).floor()).toDouble();
  final residual = rawMax / magnitude;
  final double step;
  if (residual <= 1) {
    step = 0.2;
  } else if (residual <= 2) {
    step = 0.5;
  } else if (residual <= 5) {
    step = 1;
  } else {
    step = 2;
  }
  final interval = step * magnitude;
  final maxY = (rawMax / interval).ceil() * interval;
  return ChartAxis(maxY, interval);
}
