package io.github.brandart1.better_betteruntis

import android.content.ContentResolver
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
                when (call.method) {
                    // Asks every account (Google, …) to sync its calendars now, so
                    // calendars created on the web reach the phone sooner.
                    "requestSync" -> {
                        try {
                            val extras = Bundle().apply {
                                putBoolean(ContentResolver.SYNC_EXTRAS_MANUAL, true)
                                putBoolean(ContentResolver.SYNC_EXTRAS_EXPEDITED, true)
                            }
                            ContentResolver.requestSync(null, CalendarContract.AUTHORITY, extras)
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
