package io.github.brandart1.better_betteruntis

import android.accounts.Account
import android.content.ContentResolver
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Bundle
import android.provider.CalendarContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "better_betteruntis/calendar")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "requestSync" -> result.success(requestSync())
                        "deletedCalendarIds" -> result.success(deletedCalendarIds())
                        "debugInfo" -> result.success(debugInfo())
                        "openInBrowser" -> result.success(openInBrowser(call.argument<String>("url")!!))
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("failed", e.toString(), null)
                }
            }
    }

    /** Accounts (not the local one) that have calendars on this device. */
    private fun calendarAccounts(): List<Account> {
        val out = linkedSetOf<Account>()
        contentResolver.query(
            CalendarContract.Calendars.CONTENT_URI,
            arrayOf(CalendarContract.Calendars.ACCOUNT_NAME, CalendarContract.Calendars.ACCOUNT_TYPE),
            null, null, null
        )?.use { c ->
            while (c.moveToNext()) {
                val name = c.getString(0) ?: continue
                val type = c.getString(1) ?: continue
                if (type != CalendarContract.ACCOUNT_TYPE_LOCAL) out.add(Account(name, type))
            }
        }
        return out.toList()
    }

    /**
     * Asks every account to sync its calendars now: once for all accounts and
     * once per account with calendars here. Returns what happened per request.
     */
    private fun requestSync(): List<String> {
        val extras = Bundle().apply {
            putBoolean(ContentResolver.SYNC_EXTRAS_MANUAL, true)
            putBoolean(ContentResolver.SYNC_EXTRAS_EXPEDITED, true)
        }
        val log = mutableListOf<String>()
        try {
            ContentResolver.requestSync(null, CalendarContract.AUTHORITY, extras)
            log.add("all accounts: requested")
        } catch (e: Exception) {
            log.add("all accounts: $e")
        }
        for (a in calendarAccounts()) {
            try {
                ContentResolver.requestSync(a, CalendarContract.AUTHORITY, extras)
                log.add("${a.name} (${a.type}): requested")
            } catch (e: Exception) {
                log.add("${a.name} (${a.type}): $e")
            }
        }
        return log
    }

    /** Calendars deleted elsewhere whose removal the account hasn't synced yet. */
    private fun deletedCalendarIds(): List<String> {
        val ids = mutableListOf<String>()
        contentResolver.query(
            CalendarContract.Calendars.CONTENT_URI,
            arrayOf(CalendarContract.Calendars._ID),
            "${CalendarContract.Calendars.DELETED} = 1",
            null, null
        )?.use { c -> while (c.moveToNext()) ids.add(c.getString(0)) }
        return ids
    }

    private fun debugInfo(): Map<String, Any?> {
        fun <T> safe(f: () -> T): Any? = try { f() } catch (e: Exception) { e.toString() }
        val auth = CalendarContract.AUTHORITY
        val accounts = calendarAccounts().map { a ->
            mapOf(
                "account" to "${a.name} (${a.type})",
                "syncable" to safe { ContentResolver.getIsSyncable(a, auth) },
                "autoSync" to safe { ContentResolver.getSyncAutomatically(a, auth) },
                "active" to safe { ContentResolver.isSyncActive(a, auth) },
                "pending" to safe { ContentResolver.isSyncPending(a, auth) },
            )
        }
        val calendars = mutableListOf<Map<String, Any?>>()
        contentResolver.query(
            CalendarContract.Calendars.CONTENT_URI,
            arrayOf(
                CalendarContract.Calendars._ID,
                CalendarContract.Calendars.CALENDAR_DISPLAY_NAME,
                CalendarContract.Calendars.ACCOUNT_NAME,
                CalendarContract.Calendars.ACCOUNT_TYPE,
                CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL,
                CalendarContract.Calendars.VISIBLE,
                CalendarContract.Calendars.SYNC_EVENTS,
                CalendarContract.Calendars.DELETED,
            ),
            null, null, null
        )?.use { c ->
            while (c.moveToNext()) {
                calendars.add(
                    mapOf(
                        "id" to c.getString(0),
                        "name" to c.getString(1),
                        "account" to c.getString(2),
                        "type" to c.getString(3),
                        "access" to c.getInt(4),
                        "visible" to c.getInt(5),
                        "syncEvents" to c.getInt(6),
                        "deleted" to c.getInt(7),
                    )
                )
            }
        }
        return mapOf(
            "masterSync" to safe { ContentResolver.getMasterSyncAutomatically() },
            "accounts" to accounts,
            "calendars" to calendars,
        )
    }

    /**
     * Opens [url] in a web browser, never in an app that claims the link
     * (the Google Calendar app catches calendar.google.com but can't create
     * calendars). Returns the browser package used, or null if none found.
     */
    private fun openInBrowser(url: String): String? {
        val pm = packageManager
        // A URL no app claims resolves to the default browser.
        val probe = Intent(Intent.ACTION_VIEW, Uri.parse("https://example.com/"))
            .addCategory(Intent.CATEGORY_BROWSABLE)
        val default = pm.resolveActivity(probe, PackageManager.MATCH_DEFAULT_ONLY)
            ?.activityInfo?.packageName
        val browsers = pm.queryIntentActivities(probe, 0).map { it.activityInfo.packageName }
        val pkg = when {
            default != null && default != "android" && browsers.contains(default) -> default
            browsers.contains("com.android.chrome") -> "com.android.chrome"
            else -> browsers.firstOrNull()
        } ?: return null
        startActivity(
            Intent(Intent.ACTION_VIEW, Uri.parse(url))
                .addCategory(Intent.CATEGORY_BROWSABLE)
                .setPackage(pkg)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
        return pkg
    }
}
