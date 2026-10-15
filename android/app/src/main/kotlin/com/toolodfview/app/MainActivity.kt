package com.toolodfview.app

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
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
        if (requestCode != PICK_REQUEST) return
        val reply = pickResult ?: return
        pickResult = null
        val uri = if (resultCode == Activity.RESULT_OK) data?.data else null
        reply.success(uri?.let { runCatching { copyToCache(it) }.getOrNull() })
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
    }
}
