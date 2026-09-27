/// TUI 辅助：进度格式化与简单进度条
library;

String formatProgress(int received, int total) {
  if (total <= 0) return '下载中 ${(received / 1024).toStringAsFixed(0)} KB';
  final pct = (received / total * 100).clamp(0, 100).toStringAsFixed(0);
  return '[$pct%] ${(received / 1024 / 1024).toStringAsFixed(1)}/${(total / 1024 / 1024).toStringAsFixed(1)} MB';
}

String progressBar(double ratio, {int width = 20}) {
  final filled = (ratio.clamp(0, 1) * width).round();
  return '[${'#' * filled}${' ' * (width - filled)}]';
}
