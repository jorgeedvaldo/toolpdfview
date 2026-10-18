package com.toolodfview.app

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.OpenableColumns
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Hands PDFs that other apps open or share with ToolPDF View over to the
 * Flutter side.
 *
 * `file://` URIs are passed through as a plain path. `content://` URIs (what
 * WhatsApp, Gmail, Drive and the Downloads app hand over) are streamed into the
 * app cache first, because the grant that comes with the intent does not
 * survive long enough for the viewer to re-read the document.
 */
class MainActivity : FlutterActivity() {

    private var channel: MethodChannel? = null

    /** Document delivered by the intent that started the app, if any. */
    private var pendingDocument: Map<String, String>? = null

    /** Pending reply for a [pickDocument] call. */
    private var pickResult: MethodChannel.Result? = null

    /** Pending reply for a storage access request. */
    private var accessResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "takeInitialDocument" -> {
                        result.success(pendingDocument)
                        pendingDocument = null
                    }
                    "pickDocument" -> {
                        pickResult?.success(null)
                        pickResult = result
                        openSystemPicker()
                    }
                    "hasStorageAccess" -> result.success(hasStorageAccess())
                    "requestStorageAccess" -> {
                        accessResult?.success(hasStorageAccess())
                        accessResult = result
                        requestStorageAccess()
                    }
                    else -> result.notImplemented()
                }
            }
        }
        pendingDocument = documentFrom(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val document = documentFrom(intent) ?: return
        val sink = channel
        if (sink == null) {
            pendingDocument = document
        } else {
            sink.invokeMethod("openDocument", document)
        }
    }

    /**
     * Whether the app may list the PDFs in shared storage.
     *
     * Android 11 and later answer this with "All files access"; older versions
     * with the legacy read permission.
     */
    private fun hasStorageAccess(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Environment.isExternalStorageManager()
        } else {
            checkSelfPermission(Manifest.permission.READ_EXTERNAL_STORAGE) ==
                PackageManager.PERMISSION_GRANTED
        }

    /** Asks for whichever permission this Android version needs. */
    private fun requestStorageAccess() {
        if (hasStorageAccess()) {
            accessResult?.success(true)
            accessResult = null
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            // Sends the user to the system settings page; the answer comes back
            // through onActivityResult.
            val intent = Intent(
                Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                Uri.parse("package:$packageName"),
            )
            try {
                startActivityForResult(intent, ACCESS_REQUEST)
            } catch (error: Exception) {
                startActivityForResult(
                    Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION),
                    ACCESS_REQUEST,
                )
            }
        } else {
            requestPermissions(
                arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE),
                ACCESS_REQUEST,
            )
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != ACCESS_REQUEST) return
        accessResult?.success(hasStorageAccess())
        accessResult = null
    }

    /**
     * Opens the system document picker. Used when the user would rather not
     * grant "All files access" - the picker works without any permission.
     */
    private fun openSystemPicker() {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/pdf"
            putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("application/pdf"))
        }
        try {
            startActivityForResult(intent, PICK_REQUEST)
        } catch (error: Exception) {
            pickResult?.success(null)
            pickResult = null
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        when (requestCode) {
            ACCESS_REQUEST -> {
                accessResult?.success(hasStorageAccess())
                accessResult = null
            }
            PICK_REQUEST -> {
                val reply = pickResult ?: return
                pickResult = null
                val uri = if (resultCode == Activity.RESULT_OK) data?.data else null
                reply.success(uri?.let { runCatching { copyToCache(it) }.getOrNull() })
            }
        }
    }

    private fun documentFrom(intent: Intent?): Map<String, String>? {
        if (intent == null) return null
        val uri: Uri? = when (intent.action) {
            Intent.ACTION_VIEW -> intent.data
            Intent.ACTION_SEND -> sharedStream(intent)
            else -> null
        }
        if (uri == null) return null
        return try {
            when (uri.scheme) {
                "file" -> uri.path?.let { path ->
                    mapOf("path" to path, "name" to File(path).name)
                }
                "content" -> copyToCache(uri)
                else -> null
            }
        } catch (error: Exception) {
            null
        }
    }

    private fun sharedStream(intent: Intent): Uri? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(Intent.EXTRA_STREAM) as? Uri
        }

    /** Copies [uri] into the cache directory and returns its path and name. */
    private fun copyToCache(uri: Uri): Map<String, String>? {
        val name = displayName(uri)
        val target = File(cacheDir, "shared").apply { mkdirs() }.let { File(it, name) }
        contentResolver.openInputStream(uri)?.use { input ->
            target.outputStream().use { output -> input.copyTo(output) }
        } ?: return null
        return mapOf("path" to target.absolutePath, "name" to name)
    }

    private fun displayName(uri: Uri): String {
        val fromProvider = runCatching {
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                ?.use { cursor ->
                    if (cursor.moveToFirst() && !cursor.isNull(0)) cursor.getString(0) else null
                }
        }.getOrNull()
        val name = fromProvider ?: uri.lastPathSegment?.substringAfterLast('/') ?: "document.pdf"
        val safe = name.replace(Regex("[\\\\/:*?\"<>|]"), "_").trim()
        return when {
            safe.isEmpty() -> "document.pdf"
            safe.endsWith(".pdf", ignoreCase = true) -> safe
            else -> "$safe.pdf"
        }
    }

    private companion object {
        const val CHANNEL = "com.toolodfview.app/documents"
        const val PICK_REQUEST = 0x70 // 'p'
        const val ACCESS_REQUEST = 0x61 // 'a'
    }
}
