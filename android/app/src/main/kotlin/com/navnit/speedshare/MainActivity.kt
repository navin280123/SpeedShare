package com.navnit.speedshare

import android.app.Activity
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.navnit.speedshare/fast_picker"
    private val PICK_FILES_REQUEST_CODE = 49201
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "pickFiles") {
                if (pendingResult != null) {
                    result.error("ALREADY_ACTIVE", "A file picker session is already active", null)
                    return@setMethodCallHandler
                }
                pendingResult = result

                val allowMultiple = call.argument<Boolean>("allowMultiple") ?: true
                val allowedExtensions = call.argument<List<String>>("allowedExtensions")
                val mimeType = call.argument<String>("mimeType") ?: "*/*"

                val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    putExtra(Intent.EXTRA_ALLOW_MULTIPLE, allowMultiple)
                    type = mimeType

                    if (!allowedExtensions.isNullOrEmpty()) {
                        val mimes = allowedExtensions.mapNotNull { ext ->
                            val cleanExt = ext.trim().lowercase().removePrefix(".")
                            MimeTypeMap.getSingleton().getMimeTypeFromExtension(cleanExt)
                        }.distinct().toTypedArray()
                        if (mimes.isNotEmpty()) {
                            putExtra(Intent.EXTRA_MIME_TYPES, mimes)
                        }
                    }
                }

                try {
                    startActivityForResult(intent, PICK_FILES_REQUEST_CODE)
                } catch (e: Exception) {
                    pendingResult = null
                    result.error("INTENT_ERROR", e.message, null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == PICK_FILES_REQUEST_CODE) {
            val result = pendingResult ?: return
            pendingResult = null

            if (resultCode != Activity.RESULT_OK || data == null) {
                result.success(emptyList<String>())
                return
            }

            val paths = mutableListOf<String>()
            val clipData = data.clipData
            if (clipData != null) {
                for (i in 0 until clipData.itemCount) {
                    val uri = clipData.getItemAt(i).uri
                    val path = resolveUriToPath(this, uri)
                    if (path != null) paths.add(path)
                }
            } else {
                val uri = data.data
                if (uri != null) {
                    val path = resolveUriToPath(this, uri)
                    if (path != null) paths.add(path)
                }
            }
            result.success(paths)
        }
    }

    private fun resolveUriToPath(context: Context, uri: Uri): String? {
        try {
            // 1. Document Provider
            if (DocumentsContract.isDocumentUri(context, uri)) {
                // ExternalStorageProvider
                if ("com.android.externalstorage.documents" == uri.authority) {
                    val docId = DocumentsContract.getDocumentId(uri)
                    val split = docId.split(":")
                    val type = split[0]
                    if ("primary".equals(type, ignoreCase = true)) {
                        val relPath = if (split.size > 1) split[1] else ""
                        val file = File(Environment.getExternalStorageDirectory(), relPath)
                        if (file.exists()) return file.absolutePath
                    } else {
                        // Removable SD card or secondary volume
                        val externalDirs = context.getExternalFilesDirs(null)
                        for (dir in externalDirs) {
                            if (dir != null) {
                                val abs = dir.absolutePath
                                val index = abs.indexOf(type)
                                if (index != -1) {
                                    val basePath = abs.substring(0, index + type.length)
                                    val relPath = if (split.size > 1) split[1] else ""
                                    val file = File(basePath, relPath)
                                    if (file.exists()) return file.absolutePath
                                }
                            }
                        }
                        val relPath = if (split.size > 1) split[1] else ""
                        val file = File("/storage/$type/$relPath")
                        if (file.exists()) return file.absolutePath
                    }
                }
                // MediaProvider
                else if ("com.android.providers.media.documents" == uri.authority) {
                    val docId = DocumentsContract.getDocumentId(uri)
                    val split = docId.split(":")
                    val type = split[0]
                    val id = if (split.size > 1) split[1] else split[0]

                    val contentUri = when (type.lowercase()) {
                        "image" -> MediaStore.Images.Media.EXTERNAL_CONTENT_URI
                        "video" -> MediaStore.Video.Media.EXTERNAL_CONTENT_URI
                        "audio" -> MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
                        else -> MediaStore.Files.getContentUri("external")
                    }
                    val path = getDataColumn(context, contentUri, "_id=?", arrayOf(id))
                    if (path != null && File(path).exists()) return path
                }
                // DownloadsProvider
                else if ("com.android.providers.downloads.documents" == uri.authority) {
                    val id = DocumentsContract.getDocumentId(uri)
                    if (id.startsWith("raw:")) {
                        val rawPath = id.removePrefix("raw:")
                        if (File(rawPath).exists()) return rawPath
                    }
                    if (id.startsWith("msf:")) {
                        val realId = id.split(":")[1]
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            val contentUri = MediaStore.Downloads.EXTERNAL_CONTENT_URI
                            val path = getDataColumn(context, contentUri, "_id=?", arrayOf(realId))
                            if (path != null && File(path).exists()) return path
                        }
                    }
                    try {
                        val contentUri = ContentUris.withAppendedId(
                            Uri.parse("content://downloads/public_downloads"),
                            id.toLong()
                        )
                        val path = getDataColumn(context, contentUri, null, null)
                        if (path != null && File(path).exists()) return path
                    } catch (_: Exception) {}
                }
            }

            // 2. Direct Content Scheme (MediaStore / FileProvider queries)
            if ("content".equals(uri.scheme, ignoreCase = true)) {
                val path = getDataColumn(context, uri, null, null)
                if (path != null && File(path).exists()) return path
            }

            // 3. File Scheme
            if ("file".equals(uri.scheme, ignoreCase = true)) {
                val p = uri.path
                if (p != null && File(p).exists()) return p
            }
        } catch (_: Exception) {}

        // 4. Safe fallback: Only if file is cloud-only / virtual (e.g. Google Drive)
        return copyToCacheFallback(context, uri)
    }

    private fun getDataColumn(
        context: Context,
        uri: Uri,
        selection: String?,
        selectionArgs: Array<String>?
    ): String? {
        val column = MediaStore.MediaColumns.DATA
        val projection = arrayOf(column)
        try {
            context.contentResolver.query(uri, projection, selection, selectionArgs, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val index = cursor.getColumnIndex(column)
                    if (index != -1) {
                        val str = cursor.getString(index)
                        if (!str.isNullOrEmpty() && File(str).exists()) {
                            return str
                        }
                    }
                }
            }
        } catch (_: Exception) {}
        return null
    }

    private fun copyToCacheFallback(context: Context, uri: Uri): String? {
        try {
            var fileName = "file_${System.currentTimeMillis()}"
            context.contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (nameIndex != -1) {
                        val name = cursor.getString(nameIndex)
                        if (!name.isNullOrEmpty()) fileName = name
                    }
                }
            }

            val cacheDir = File(context.cacheDir, "fast_picker")
            if (!cacheDir.exists()) cacheDir.mkdirs()
            val destFile = File(cacheDir, "${System.currentTimeMillis()}_$fileName")

            context.contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(destFile).use { output ->
                    val buffer = ByteArray(65536) // 64 KB buffer
                    var read: Int
                    while (input.read(buffer).also { read = it } != -1) {
                        output.write(buffer, 0, read)
                    }
                    output.flush()
                }
            }
            return if (destFile.exists()) destFile.absolutePath else null
        } catch (_: Exception) {
            return null
        }
    }
}
