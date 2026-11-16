package io.github.brandart1.better_betteruntis

import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * In-app updater (`better_betteruntis/updater`): installs an APK the Dart
 * side downloaded and verified, through a PackageInstaller session. No
 * FileProvider or third-party plugin needed.
 */
class AppUpdater(private val activity: Activity) : MethodChannel.MethodCallHandler {
    private val main = Handler(Looper.getMainLooper())

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "canRequestInstalls" -> result.success(canRequestInstalls())
                "openInstallSettings" -> {
                    openInstallSettings()
                    result.success(null)
                }
                "install" -> install(call.argument<String>("path")!!, result)
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("failed", e.toString(), null)
        }
    }

    private fun canRequestInstalls(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
            activity.packageManager.canRequestPackageInstalls()

    private fun openInstallSettings() {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:${activity.packageName}"),
            )
        } else {
            Intent(Settings.ACTION_SECURITY_SETTINGS)
        }
        activity.startActivity(intent)
    }

    private fun install(path: String, result: MethodChannel.Result) {
        if (!canRequestInstalls()) {
            result.success(mapOf("status" to "notAllowed"))
            return
        }
        val file = File(path)
        if (!file.isFile) {
            result.success(mapOf("status" to "failure", "message" to "APK not found"))
            return
        }
        // A new install replaces any earlier unanswered one.
        pending?.let { deliver(it, "aborted", "Superseded by a new installation") }
        pending = result
        // Writing the APK into the session is disk I/O: off the main thread.
        Thread {
            try {
                val installer = activity.packageManager.packageInstaller
                val params = PackageInstaller.SessionParams(
                    PackageInstaller.SessionParams.MODE_FULL_INSTALL,
                ).apply {
                    setAppPackageName(activity.packageName)
                    setSize(file.length())
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        // Silent once we are the installer of record.
                        setRequireUserAction(
                            PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED,
                        )
                    }
                }
                val sessionId = installer.createSession(params)
                installer.openSession(sessionId).use { session ->
                    file.inputStream().use { input ->
                        session.openWrite("base.apk", 0, file.length()).use { out ->
                            input.copyTo(out)
                            session.fsync(out)
                        }
                    }
                    val intent = Intent(activity, UpdateInstallReceiver::class.java)
                        .setAction(ACTION_INSTALL_STATUS)
                        .setPackage(activity.packageName)
                    var flags = PendingIntent.FLAG_UPDATE_CURRENT
                    // The installer adds the status extras: must be mutable.
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        flags = flags or PendingIntent.FLAG_MUTABLE
                    }
                    val pi = PendingIntent.getBroadcast(activity, sessionId, intent, flags)
                    session.commit(pi.intentSender)
                }
            } catch (e: Exception) {
                main.post { pending?.let { deliver(it, "failure", e.message ?: e.toString()) } }
            }
        }.start()
    }

    companion object {
        const val ACTION_INSTALL_STATUS =
            "io.github.brandart1.better_betteruntis.INSTALL_STATUS"

        /** The Dart `install` call waiting for a final status. */
        private var pending: MethodChannel.Result? = null

        private fun deliver(result: MethodChannel.Result, status: String, message: String?) {
            if (pending === result) pending = null
            result.success(mapOf("status" to status, "message" to message))
        }

        /** Called by [UpdateInstallReceiver] on the main thread. */
        fun onStatus(context: Context, intent: Intent) {
            val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)
            val message = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)
            when (status) {
                PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                    @Suppress("DEPRECATION")
                    val confirm: Intent? =
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
                        } else {
                            intent.getParcelableExtra(Intent.EXTRA_INTENT)
                        }
                    if (confirm == null) {
                        pending?.let { deliver(it, "failure", "No confirmation dialog") }
                        return
                    }
                    try {
                        context.startActivity(confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    } catch (e: Exception) {
                        pending?.let { deliver(it, "failure", e.message ?: e.toString()) }
                    }
                }
                PackageInstaller.STATUS_SUCCESS -> pending?.let { deliver(it, "success", message) }
                PackageInstaller.STATUS_FAILURE_ABORTED -> pending?.let { deliver(it, "aborted", message) }
                else -> pending?.let { deliver(it, "failure", message ?: "status $status") }
            }
        }
    }
}

/** Receives PackageInstaller session status broadcasts (not exported). */
class UpdateInstallReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == AppUpdater.ACTION_INSTALL_STATUS) {
            AppUpdater.onStatus(context, intent)
        }
    }
}
