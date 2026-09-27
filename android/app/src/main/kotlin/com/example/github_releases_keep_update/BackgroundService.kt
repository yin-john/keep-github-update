package com.example.github_releases_keep_update

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * 常驻前台服务：显示「常驻通知栏」通知，同时把进程保活在后台，
 * 使按间隔的自动检测在应用退到后台后仍能继续。
 */
class BackgroundService : Service() {

    companion object {
        const val CHANNEL_ID = "grku_background"
        const val NOTIFICATION_ID = 1001
        const val EXTRA_TITLE = "title"
        const val EXTRA_TEXT = "text"
        const val ACTION_START = "grku.action.START"
        const val ACTION_UPDATE = "grku.action.UPDATE"
        const val ACTION_STOP = "grku.action.STOP"

        @Volatile
        private var running = false

        fun isRunning(): Boolean = running

        /** 启动常驻服务（应用处于前台时调用，避免后台启动限制） */
        fun start(context: Context, title: String?, text: String?) {
            val intent = Intent(context, BackgroundService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_TITLE, title)
                putExtra(EXTRA_TEXT, text)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        /** 更新常驻通知文案 */
        fun update(context: Context, title: String?, text: String?) {
            if (!running) return
            val intent = Intent(context, BackgroundService::class.java).apply {
                action = ACTION_UPDATE
                putExtra(EXTRA_TITLE, title)
                putExtra(EXTRA_TEXT, text)
            }
            try {
                context.startService(intent)
            } catch (_: Exception) {
                // 服务已被系统回收时忽略
            }
        }

        /**
         * 停止常驻服务。
         *
         * 必须用 stopService（而不是 startService(ACTION_STOP)）：
         * 后者会「先把服务拉起来、再让它执行 STOP 分支而不调用 startForeground()」，
         * 若期间又收到 startForegroundService，系统会抛
         * RemoteServiceException: Context.startForegroundService() did not then call
         * Service.startForeground() 导致进程崩溃。
         */
        fun stop(context: Context) {
            try {
                context.stopService(Intent(context, BackgroundService::class.java))
            } catch (_: Exception) {
                // 服务未运行时忽略
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            running = false
            stopForegroundCompat()
            stopSelf()
            return START_NOT_STICKY
        }
        // 只要是经 startForegroundService 拉起的服务，就必须在超时前调用 startForeground()；
        // 因此除 STOP 外的所有 action（含 UPDATE、null）都统一走 startForeground，
        // 并且整体兜底：任何异常都不能让应用进程崩溃。
        return try {
            val n = buildNotification(
                intent?.getStringExtra(EXTRA_TITLE) ?: "GRKU 后台运行中",
                intent?.getStringExtra(EXTRA_TEXT) ?: "正在按设定的间隔检测更新"
            )
            startForegroundCompat(n)
            running = true
            START_STICKY
        } catch (e: Exception) {
            // 常驻通知创建/前台化失败（如缺少权限、被系统限制）时安静退出，不影响前台使用
            running = false
            try {
                stopForegroundCompat()
            } catch (_: Exception) {
            }
            stopSelf()
            START_NOT_STICKY
        }
    }

    override fun onDestroy() {
        running = false
        super.onDestroy()
    }

    private fun startForegroundCompat(n: Notification) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID, n,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            )
        } else {
            startForeground(NOTIFICATION_ID, n)
        }
    }

    private fun stopForegroundCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
    }

    private fun notificationManager(): NotificationManager =
        getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private fun buildNotification(title: String, text: String): Notification {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "GRKU 后台运行",
                NotificationManager.IMPORTANCE_LOW // 常驻通知不发声、不打扰
            ).apply {
                description = "自动检测更新时的常驻通知"
                setShowBadge(false)
            }
            notificationManager().createNotificationChannel(channel)
        }

        val launch = packageManager.getLaunchIntentForPackage(packageName)
        val pending = if (launch != null) {
            PendingIntent.getActivity(
                this, 0, launch,
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                } else {
                    PendingIntent.FLAG_UPDATE_CURRENT
                }
            )
        } else {
            null
        }

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(android.R.drawable.stat_notify_sync)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .apply { if (pending != null) setContentIntent(pending) }
            .build()
    }
}
