package com.onethelab.searchitlauncher

import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

/**
 * Hosts the platform channel that lets the Flutter launcher query, launch and
 * manage the apps installed on the device.
 */
class MainActivity : FlutterActivity() {

    private val channelName = "searchit/apps"
    private val iconSize = 128
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getApps" -> loadApps(result)
                    "launchApp" -> {
                        val ok = launchApp(call.argument<String>("package"))
                        result.success(ok)
                    }
                    "uninstallApp" -> {
                        openIntent(Intent(Intent.ACTION_DELETE).apply {
                            data = Uri.parse("package:${call.argument<String>("package")}")
                        })
                        result.success(null)
                    }
                    "openAppInfo" -> {
                        openIntent(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                            data = Uri.parse("package:${call.argument<String>("package")}")
                        })
                        result.success(null)
                    }
                    "openPlayStore" -> {
                        openPlayStore(call.argument<String>("package"))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /** Enumerates every app that exposes a launchable activity. */
    private fun loadApps(result: MethodChannel.Result) {
        Thread {
            val pm = packageManager
            val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
            val resolved = pm.queryIntentActivities(intent, 0)
            val apps = ArrayList<Map<String, Any?>>()
            val seen = HashSet<String>()
            for (info in resolved) {
                val pkg = info.activityInfo.packageName
                // The launcher hides no apps — even SearchIt itself is listed.
                if (!seen.add(pkg)) continue
                try {
                    val appInfo = pm.getApplicationInfo(pkg, 0)
                    val pkgInfo = pm.getPackageInfo(pkg, 0)
                    apps.add(
                        mapOf(
                            "label" to info.loadLabel(pm).toString(),
                            "package" to pkg,
                            "firstInstallTime" to pkgInfo.firstInstallTime,
                            "system" to ((appInfo.flags and ApplicationInfo.FLAG_SYSTEM) != 0),
                            "icon" to drawableToPng(info.loadIcon(pm)),
                        )
                    )
                } catch (_: PackageManager.NameNotFoundException) {
                    // App vanished between query and lookup; skip it.
                }
            }
            mainHandler.post { result.success(apps) }
        }.start()
    }

    private fun launchApp(pkg: String?): Boolean {
        if (pkg == null) return false
        val intent = packageManager.getLaunchIntentForPackage(pkg) ?: return false
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
        return true
    }

    private fun openPlayStore(pkg: String?) {
        if (pkg == null) return
        val market = Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=$pkg"))
        if (market.resolveActivity(packageManager) != null) {
            openIntent(market)
        } else {
            openIntent(
                Intent(Intent.ACTION_VIEW, Uri.parse("https://play.google.com/store/apps/details?id=$pkg"))
            )
        }
    }

    private fun openIntent(intent: Intent) {
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            startActivity(intent)
        } catch (_: Exception) {
            // No activity available to handle the intent; ignore.
        }
    }

    /** Renders a drawable into a fixed-size PNG byte array for Flutter. */
    private fun drawableToPng(drawable: Drawable): ByteArray {
        val bitmap = if (drawable is BitmapDrawable && drawable.bitmap != null) {
            Bitmap.createScaledBitmap(drawable.bitmap, iconSize, iconSize, true)
        } else {
            val bmp = Bitmap.createBitmap(iconSize, iconSize, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bmp)
            drawable.setBounds(0, 0, iconSize, iconSize)
            drawable.draw(canvas)
            bmp
        }
        val stream = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
        return stream.toByteArray()
    }
}
