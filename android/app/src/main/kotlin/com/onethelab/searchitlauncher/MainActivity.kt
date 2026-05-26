package com.onethelab.searchitlauncher

import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.provider.Settings.ACTION_HOME_SETTINGS
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File

/**
 * Hosts the platform channel that lets the Flutter launcher query, launch and
 * manage the apps installed on the device.
 */
class MainActivity : FlutterActivity() {

    private val channelName = "searchit/apps"
    private val iconSize = 72   // 52px display size; 72px gives ~1.4× margin for density
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
                    "openHomeSettings" -> {
                        openIntent(Intent(ACTION_HOME_SETTINGS))
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
                    @Suppress("DEPRECATION")
                    val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                        pkgInfo.longVersionCode
                    } else {
                        pkgInfo.versionCode.toLong()
                    }
                    val iconBytes = cachedIcon(pkg, versionCode) {
                        drawableToPng(info.loadIcon(pm))
                    }
                    apps.add(
                        mapOf(
                            "label" to info.loadLabel(pm).toString(),
                            "package" to pkg,
                            "firstInstallTime" to pkgInfo.firstInstallTime,
                            "system" to ((appInfo.flags and ApplicationInfo.FLAG_SYSTEM) != 0),
                            "icon" to iconBytes,
                        )
                    )
                } catch (_: PackageManager.NameNotFoundException) {
                    // App vanished between query and lookup; skip it.
                }
            }
            pruneIconCache(seen)
            mainHandler.post { result.success(apps) }
        }.start()
    }

    /**
     * Returns cached icon bytes for [pkg] at [versionCode], generating and
     * storing them via [generate] on a cache miss. A corrupted cache file is
     * treated as a miss and overwritten.
     */
    private fun cachedIcon(
        pkg: String,
        versionCode: Long,
        generate: () -> ByteArray,
    ): ByteArray {
        val file = iconCacheFile(pkg, versionCode)
        if (file.exists()) {
            try { return file.readBytes() } catch (_: Exception) { /* corrupted — regenerate */ }
        }
        val bytes = generate()
        try { file.writeBytes(bytes) } catch (_: Exception) { /* disk full — skip cache */ }
        return bytes
    }

    /** Returns the cache file path for a given package + version pair. */
    private fun iconCacheFile(pkg: String, versionCode: Long): File {
        val dir = File(cacheDir, "icons").apply { mkdirs() }
        return File(dir, "${pkg}_$versionCode.png")
    }

    /**
     * Deletes cached icon files for packages no longer present on the device
     * so the icon cache does not grow unboundedly.
     */
    private fun pruneIconCache(currentPackages: Set<String>) {
        val iconDir = File(cacheDir, "icons")
        if (!iconDir.exists()) return
        iconDir.listFiles()?.forEach { file ->
            val pkg = file.name.substringBeforeLast('_')
            if (pkg !in currentPackages) file.delete()
        }
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
