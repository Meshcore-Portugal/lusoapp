int batteryPercentFromMv(int mv, {int emptyMv = 3000, int fullMv = 4200}) {
  if (mv <= 0) return 0;
  final clamped = mv.clamp(emptyMv, fullMv);
  final span = fullMv - emptyMv;
  if (span <= 0) return 0;
  return (((clamped - emptyMv) / span) * 100).round();
}
