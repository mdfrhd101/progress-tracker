package com.example.progress_tracker

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.annotation.NonNull
import androidx.core.content.FileProvider
import java.io.File
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Bridges the Do-Not-Disturb (Deep Focus) controls to Dart.
 *
 * Everything is defensive: on any older OS / missing permission / error we
 * return a safe value instead of throwing, so a failed DND toggle can never
 * crash or block a focus session.
 */
class MainActivity : FlutterActivity() {

    private val channel = "com.octagram.progress_tracker/dnd"

    private val platformChannel = "com.octagram.progress_tracker/platform"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Permission-free helpers (open a URL in the system browser).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, platformChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openUrl" -> {
                        val url = call.argument<String>("url")
                        if (url.isNullOrBlank()) { result.success(false); return@setMethodCallHandler }
                        try {
                            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    // Primary device ABI, e.g. "arm64-v8a" (picks the matching release asset).
                    "getAbi" -> result.success(Build.SUPPORTED_ABIS.firstOrNull() ?: "arm64-v8a")

                    // Hands a downloaded APK to the system installer. Returns
                    // "ok", "permission" (user must allow installs), or "error".
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) { result.success("error"); return@setMethodCallHandler }
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                                !packageManager.canRequestPackageInstalls()) {
                                val i = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                    Uri.parse("package:$packageName")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                startActivity(i)
                                result.success("permission")
                                return@setMethodCallHandler
                            }
                            val file = File(path)
                            val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
                            val intent = Intent(Intent.ACTION_VIEW)
                                .setDataAndType(uri, "application/vnd.android.package-archive")
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            startActivity(intent)
                            result.success("ok")
                        } catch (e: Exception) {
                            result.success("error")
                        }
                    }

                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                when (call.method) {

                    // Is ACCESS_NOTIFICATION_POLICY granted? (API 23+)
                    "isDndPermissionGranted" -> {
                        val granted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            nm.isNotificationPolicyAccessGranted
                        } else {
                            false
                        }
                        result.success(granted)
                    }

                    // Open the system screen where the user grants DND access.
                    "openDndSettings" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            val intent = Intent(
                                Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS
                            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                        }
                        result.success(null)
                    }

                    // Turn ON total-silence DND. Returns true only if it took effect.
                    "enableDnd" -> {
                        result.success(setFilter(nm, totalSilence = true))
                    }

                    // Restore the phone to normal ringer/notifications.
                    "disableDnd" -> {
                        result.success(setFilter(nm, totalSilence = false))
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun setFilter(nm: NotificationManager, totalSilence: Boolean): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return false
        if (!nm.isNotificationPolicyAccessGranted) return false
        return try {
            val filter = if (totalSilence) {
                NotificationManager.INTERRUPTION_FILTER_NONE // mutes calls, SMS, notifications
            } else {
                NotificationManager.INTERRUPTION_FILTER_ALL  // back to normal
            }
            nm.setInterruptionFilter(filter)
            true
        } catch (e: Exception) {
            false
        }
    }
}
