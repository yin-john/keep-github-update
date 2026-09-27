package com.example.github_releases_keep_update

import android.Manifest
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.content.pm.Signature
import android.graphics.Bitmap
import android.graphics.Canvas
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest

/**
 * Flutter 与系统能力之间的桥：权限、root / Shizuku、APK 签名与包信息。
 * 通道名：grku/native
 */
class MainActivity : FlutterActivity() {
    private val requestStorageCode = 1001
    private val requestNotificationCode = 1002

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "grku/native")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasStoragePermission" -> result.success(hasStoragePermission())
                    "requestStoragePermission" -> result.success(requestStoragePermission())
                    "hasNotificationPermission" -> result.success(hasNotificationPermission())
                    "requestNotificationPermission" -> result.success(requestNotificationPermission())
                    "hasRoot", "requestRoot" -> checkRootAsync(result)
                    "hasShizuku", "requestShizuku" -> checkShizukuAsync(result)
                    "apkSignature" -> result.success(apkSignature(call.argument<String>("path")))
                    "apkPackageName" -> result.success(apkPackageName(call.argument<String>("path")))
                    "installedSignature" -> result.success(installedSignature(call.argument<String>("package")))
                    "installedVersion" -> result.success(installedVersion(call.argument<String>("package")))
                    // 自身包名（applicationId）：用于识别「自己更新自己」，避免误卸载自身
                    "selfPackageName" -> result.success(packageName)
                    // 读取 APK 的软件名称与图标（图标导出为 PNG）
                    "apkAppInfo" -> result.success(apkAppInfo(call.argument<String>("path")))
                    // 常驻通知栏 + 后台保活（前台服务）
                    "startBackgroundService" -> result.success(
                        startBackgroundService(
                            call.argument<String>("title"),
                            call.argument<String>("text")
                        )
                    )
                    "updateBackgroundNotification" -> result.success(
                        updateBackgroundNotification(
                            call.argument<String>("title") ?: "GRKU 后台运行中",
                            call.argument<String>("text") ?: ""
                        )
                    )
                    "stopBackgroundService" -> result.success(stopBackgroundService())
                    "isBackgroundServiceRunning" -> result.success(BackgroundService.isRunning())
                    "installWithSystem" -> result.success(installWithSystem(call.argument<String>("path")))
                    "filesDir" -> result.success(filesDir.absolutePath)
                    "externalFilesDir" -> result.success(getExternalFilesDir(null)?.absolutePath)
                    else -> result.notImplemented()
                }
            }
    }

    // —— 权限 ——

    private fun hasStoragePermission(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Environment.isExternalStorageManager()
        } else {
            checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) ==
                PackageManager.PERMISSION_GRANTED
        }

    /** 打开「所有文件访问」授权页；旧版本直接申请写外部存储 */
    private fun requestStoragePermission(): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                startActivity(
                    Intent(
                        Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                        Uri.parse("package:$packageName")
                    )
                )
            } else {
                requestPermissions(
                    arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
                    requestStorageCode
                )
            }
            true
        } catch (e: Exception) {
            // 个别 ROM 没有该设置页，退回应用详情页让用户手动授权
            try {
                startActivity(
                    Intent(
                        Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                        Uri.parse("package:$packageName")
                    )
                )
                true
            } catch (e2: Exception) {
                false
            }
        }
    }

    private fun hasNotificationPermission(): Boolean =
        if (Build.VERSION.SDK_INT >= 33) {
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED
        } else {
            true
        }

    private fun requestNotificationPermission(): Boolean {
        if (Build.VERSION.SDK_INT >= 33) {
            requestPermissions(
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                requestNotificationCode
            )
        }
        return true
    }

    /** 普通安装：交给系统安装器（用户手动确认），需要 FileProvider 提供 content:// URI */
    private fun installWithSystem(path: String?): Boolean {
        if (path == null) return false
        val file = java.io.File(path)
        if (!file.exists()) return false
        return try {
            val uri = androidx.core.content.FileProvider.getUriForFile(
                this, "$packageName.fileprovider", file
            )
            val intent = Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
                data = uri
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                putExtra(Intent.EXTRA_NOT_UNKNOWN_SOURCE, true)
            }
            startActivity(intent)
            true
        } catch (e: Exception) {
            false
        }
    }

    // —— root / Shizuku（可能弹授权框，放到后台线程避免 ANR）——

    private fun checkRootAsync(result: MethodChannel.Result) {
        runShell(result) {
            val p = Runtime.getRuntime().exec(arrayOf("su", "-c", "id"))
            val out = p.inputStream.bufferedReader().readText()
            p.waitFor()
            p.exitValue() == 0 && out.contains("uid=0")
        }
    }

    private fun checkShizukuAsync(result: MethodChannel.Result) {
        runShell(result) {
            val p = Runtime.getRuntime().exec(arrayOf("shizuku", "-v"))
            val out = p.inputStream.bufferedReader().readText()
            p.waitFor()
            p.exitValue() == 0 && out.isNotBlank()
        }
    }

    private fun runShell(result: MethodChannel.Result, block: () -> Boolean) {
        Thread {
            val ok = try {
                block()
            } catch (e: Exception) {
                false
            }
            runOnUiThread { result.success(ok) }
        }.start()
    }

    // —— APK / 已安装应用签名与版本 ——

    @Suppress("DEPRECATION")
    private fun certFlags(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            PackageManager.GET_SIGNING_CERTIFICATES
        } else {
            PackageManager.GET_SIGNATURES
        }

    @Suppress("DEPRECATION")
    private fun legacyFirstSignature(info: PackageInfo): Signature? =
        info.signatures?.firstOrNull()

    private fun signerDigest(info: PackageInfo?): String? {
        if (info == null) return null
        val sig = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.signingInfo?.apkContentsSigners?.firstOrNull()
        } else {
            legacyFirstSignature(info)
        } ?: return null
        val digest = MessageDigest.getInstance("SHA-256").digest(sig.toByteArray())
        return digest.joinToString("") { "%02x".format(it.toInt() and 0xff) }
    }

    private fun apkSignature(path: String?): String? {
        if (path == null) return null
        return try {
            signerDigest(packageManager.getPackageArchiveInfo(path, certFlags()))
        } catch (e: Exception) {
            null
        }
    }

    private fun apkPackageName(path: String?): String? {
        if (path == null) return null
        return try {
            packageManager.getPackageArchiveInfo(path, 0)?.packageName
        } catch (e: Exception) {
            null
        }
    }

    private fun installedSignature(pkg: String?): String? {
        if (pkg == null) return null
        return try {
            signerDigest(packageManager.getPackageInfo(pkg, certFlags()))
        } catch (e: Exception) {
            null
        }
    }

    private fun installedVersion(pkg: String?): String? {
        if (pkg == null) return null
        return try {
            packageManager.getPackageInfo(pkg, 0).versionName
        } catch (e: Exception) {
            null
        }
    }

    // —— APK 的软件名称与图标 ——

    /** 读取 APK 的软件名称（应用标签）与图标；图标导出为 PNG，返回其路径 */
    private fun apkAppInfo(path: String?): Map<String, Any?>? {
        if (path == null) return null
        return try {
            val info = packageManager.getPackageArchiveInfo(path, 0) ?: return null
            val appInfo = info.applicationInfo ?: return null
            // 未安装的 APK 需要显式指定路径，loadLabel / loadIcon 才能读到资源
            appInfo.sourceDir = path
            appInfo.publicSourceDir = path
            val label = try {
                appInfo.loadLabel(packageManager).toString()
            } catch (e: Exception) {
                info.packageName
            }
            mapOf(
                "label" to label,
                "iconPath" to saveApkIcon(appInfo, info.packageName),
                "packageName" to info.packageName,
                "version" to info.versionName
            )
        } catch (e: Exception) {
            null
        }
    }

    /** 把 APK 图标绘制为 144×144 的 PNG，存到应用私有目录 */
    private fun saveApkIcon(appInfo: android.content.pm.ApplicationInfo, pkg: String): String? {
        return try {
            val drawable = appInfo.loadIcon(packageManager)
            val size = 144
            val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)
            drawable.setBounds(0, 0, canvas.width, canvas.height)
            drawable.draw(canvas)
            val dir = File(filesDir, "grku_icons").apply { mkdirs() }
            val out = File(dir, "$pkg.png")
            FileOutputStream(out).use { stream ->
                bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
            }
            bitmap.recycle()
            out.absolutePath
        } catch (e: Exception) {
            null
        }
    }

    // —— 常驻通知栏 + 后台保活 ——

    private fun startBackgroundService(title: String?, text: String?): Boolean {
        return try {
            BackgroundService.start(this, title, text)
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun updateBackgroundNotification(title: String, text: String): Boolean {
        return try {
            BackgroundService.update(this, title, text)
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun stopBackgroundService(): Boolean {
        return try {
            BackgroundService.stop(this)
            true
        } catch (e: Exception) {
            false
        }
    }
}
