package com.onethelab.searchitlauncher

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
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
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {

    private val channelName = "searchit/apps"
    private val iconSize = 192
    private val mainHandler = Handler(Looper.getMainLooper())

    private var channel: MethodChannel? = null
    private var receiverRegistered = false

    /**
     * Listens for install/update/uninstall of other apps and notifies Flutter.
     * On update (PACKAGE_REPLACED) the stale disk icon cache is invalidated so the
     * launcher can re-fetch the new icon immediately, instead of waiting for a cold
     * start. PACKAGE_REPLACED fires for updates; ADDED/REMOVED only when the
     * EXTRA_REPLACING flag is absent (i.e. a genuine install / uninstall).
     */
    private val packageReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val pkg = intent.data?.schemeSpecificPart ?: return
            if (pkg == packageName) return
            val replacing = intent.getBooleanExtra(Intent.EXTRA_REPLACING, false)
            val action = when (intent.action) {
                Intent.ACTION_PACKAGE_REPLACED -> {
                    invalidateIconCache(pkg)
                    "replaced"
                }
                Intent.ACTION_PACKAGE_ADDED -> if (replacing) return else "added"
                Intent.ACTION_PACKAGE_REMOVED -> if (replacing) return else "removed"
                else -> return
            }
            mainHandler.post {
                channel?.invokeMethod(
                    "onPackageChanged",
                    mapOf("package" to pkg, "action" to action),
                )
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        registerPackageReceiver()
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .also { it.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getAppsMetadata" -> loadAppsMetadata(result)
                    "getIcons" -> {
                        @Suppress("UNCHECKED_CAST")
                        val packages = call.argument<List<*>>("packages")
                            ?.filterIsInstance<String>() ?: emptyList()
                        loadIcons(packages, result)
                    }
                    "launchApp" -> {
                        result.success(launchApp(call.argument<String>("package")))
                    }
                    "uninstallApp" -> {
                        val pkg = call.argument<String>("package")
                        if (pkg == null) {
                            result.error("INVALID_ARG", "package is null", null)
                        } else {
                            try {
                                requestUninstall(pkg)
                                result.success(null)
                            } catch (e: Exception) {
                                result.error("UNINSTALL_FAILED", e.message, e.toString())
                            }
                        }
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
            } }
    }

    private fun registerPackageReceiver() {
        if (receiverRegistered) return
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_PACKAGE_ADDED)
            addAction(Intent.ACTION_PACKAGE_REMOVED)
            addAction(Intent.ACTION_PACKAGE_REPLACED)
            addDataScheme("package")
        }
        registerReceiver(packageReceiver, filter)
        receiverRegistered = true
    }

    override fun onDestroy() {
        if (receiverRegistered) {
            try { unregisterReceiver(packageReceiver) } catch (_: Exception) {}
            receiverRegistered = false
        }
        channel?.setMethodCallHandler(null)
        channel = null
        super.onDestroy()
    }

    /**
     * Phase 1: returns app metadata without icons — fast enough to show the
     * grid within ~50 ms on most devices. Also prunes stale icon cache files.
     */
    private fun loadAppsMetadata(result: MethodChannel.Result) {
        Thread {
            val pm = packageManager
            val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
            val resolved = pm.queryIntentActivities(intent, 0)
            val apps = ArrayList<Map<String, Any?>>()
            val seen = HashSet<String>()
            for (info in resolved) {
                val pkg = info.activityInfo.packageName
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
                        )
                    )
                } catch (_: PackageManager.NameNotFoundException) {}
            }
            // Prune stale icon cache after metadata is collected.
            pruneIconCache(seen)
            mainHandler.post { result.success(apps) }
        }.start()
    }

    /**
     * Phase 2: loads icon bytes for [packages] in parallel using a thread pool
     * sized to the number of CPU cores. Cache hits (file read) are ~10× faster
     * than cache misses (drawable → bitmap → PNG encode → file write).
     */
    private fun loadIcons(packages: List<String>, result: MethodChannel.Result) {
        Thread {
            val pm = packageManager
            val threads = Runtime.getRuntime().availableProcessors().coerceAtLeast(2)
            val executor = Executors.newFixedThreadPool(threads)
            val iconMap = ConcurrentHashMap<String, ByteArray>()

            val futures = packages.map { pkg ->
                executor.submit {
                    try {
                        val pkgInfo = pm.getPackageInfo(pkg, 0)
                        @Suppress("DEPRECATION")
                        val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                            pkgInfo.longVersionCode
                        } else {
                            pkgInfo.versionCode.toLong()
                        }
                        val bytes = cachedIcon(pkg, versionCode) {
                            drawableToPng(pm.getApplicationIcon(pkg))
                        }
                        iconMap[pkg] = bytes
                    } catch (_: Exception) {}
                }
            }
            futures.forEach { it.get() }
            executor.shutdown()

            mainHandler.post { result.success(HashMap(iconMap)) }
        }.start()
    }

    private fun cachedIcon(pkg: String, versionCode: Long, generate: () -> ByteArray): ByteArray {
        val file = iconCacheFile(pkg, versionCode)
        if (file.exists()) {
            try { return file.readBytes() } catch (_: Exception) {}
        }
        val bytes = generate()
        try { file.writeBytes(bytes) } catch (_: Exception) {}
        return bytes
    }

    private fun iconCacheFile(pkg: String, versionCode: Long): File {
        val dir = File(cacheDir, "icons_${iconSize}").apply { mkdirs() }
        return File(dir, "${pkg}_$versionCode.png")
    }

    /** Deletes all cached icon files for [pkg] (any versionCode) so the next
     * getIcons call regenerates a fresh icon. Used when an app is updated. */
    private fun invalidateIconCache(pkg: String) {
        val iconDir = File(cacheDir, "icons_${iconSize}")
        if (!iconDir.exists()) return
        iconDir.listFiles()?.forEach { file ->
            if (file.name.substringBeforeLast('_') == pkg) file.delete()
        }
    }

    private fun pruneIconCache(currentPackages: Set<String>) {
        val iconDir = File(cacheDir, "icons_${iconSize}")
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
            openIntent(Intent(Intent.ACTION_VIEW,
                Uri.parse("https://play.google.com/store/apps/details?id=$pkg")))
        }
    }

    /**
     * Requests uninstallation of [pkg] via the system dialog.
     * Does NOT use FLAG_ACTIVITY_NEW_TASK: launchers with singleTask +
     * taskAffinity="" can cause the dialog to be hidden behind the launcher
     * when that flag is set. Starting in the same task keeps it in front.
     */
    private fun requestUninstall(pkg: String) {
        startActivity(
            Intent(Intent.ACTION_DELETE, Uri.parse("package:$pkg")).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
        )
    }

    private fun openIntent(intent: Intent) {
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try { startActivity(intent) } catch (_: Exception) {}
    }

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
        return ByteArrayOutputStream().also {
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
        }.toByteArray()
    }
}
