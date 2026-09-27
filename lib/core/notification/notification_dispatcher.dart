/// 通知分发器：按仓库/全局开关聚合「系统通知」与「Webhook」
library;

import '../config/models.dart';
import 'system_notifier.dart';
import 'webhook_notifier.dart';

class NotificationDispatcher {

  NotificationDispatcher({
    required this.system,
    required this.webhook,
    required this.config,
  });
  final SystemNotifier system;
  final WebhookNotifier webhook;
  final AppConfig config;

  Future<void> dispatch(
    NotificationEvent event,
    RepoConfig repo,
    String tag,
    PlatformType platform, {
    String? message,
  }) async {
    final title = _title(event, repo, tag);
    final body = message ?? _body(event, platform);
    final level = _level(event);

    if (config.systemNotificationsEnabled && repo.notificationsEnabled) {
      await system.show(title, body, level);
    }

    final wc = config.webhook;
    final repoWh = repo.webhook;
    final whEnabled = repoWh?.enabled ?? wc.enabled;
    if (whEnabled) {
      final useGlobalFilter = repoWh == null;
      if (!useGlobalFilter || wc.events.contains(event)) {
        final url = repoWh?.url ?? wc.url;
        if (url.isNotEmpty) {
          final payload = {
            'event': event.name,
            'repo': repo.fullName,
            'tag': tag,
            'platform': platform.name,
            'message': message,
            'timestamp': DateTime.now().toIso8601String(),
          };
          await webhook.post(url, payload,
              secret: wc.secret, headers: wc.headers);
        }
      }
    }
  }

  String _title(NotificationEvent e, RepoConfig repo, String tag) {
    switch (e) {
      case NotificationEvent.updateAvailable:
        return '${repo.fullName} 有可用更新';
      case NotificationEvent.updateStarted:
        return '${repo.fullName} 更新开始';
      case NotificationEvent.updateSuccess:
        return '${repo.fullName} 更新成功';
      case NotificationEvent.updateFailed:
        return '${repo.fullName} 更新失败';
    }
  }

  String _body(NotificationEvent e, PlatformType platform) {
    switch (e) {
      case NotificationEvent.updateAvailable:
        return '检测到适用于 ${platform.name} 的新版本';
      case NotificationEvent.updateStarted:
        return '正在下载并应用更新…';
      case NotificationEvent.updateSuccess:
        return '已成功更新到最新版本';
      case NotificationEvent.updateFailed:
        return '更新过程出错';
    }
  }

  NotificationLevel _level(NotificationEvent e) {
    switch (e) {
      case NotificationEvent.updateAvailable:
        return NotificationLevel.info;
      case NotificationEvent.updateStarted:
        return NotificationLevel.info;
      case NotificationEvent.updateSuccess:
        return NotificationLevel.success;
      case NotificationEvent.updateFailed:
        return NotificationLevel.error;
    }
  }
}
