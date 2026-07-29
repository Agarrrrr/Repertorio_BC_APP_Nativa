package com.lldm.bc.repertorio_bc

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream

class MainActivity : FlutterActivity() {
    private val channelName = "com.lldm.bc/file_saver"
    private val createFileRequest = 4101
    private val chooseFolderRequest = 4102
    private var pendingResult: MethodChannel.Result? = null
    private var pendingFiles: List<SaveFile> = emptyList()

    data class SaveFile(
        val path: String,
        val name: String,
        val mimeType: String,
    )

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName,
        ).setMethodCallHandler { call, result ->
            if (call.method == "saveFiles") {
                startSave(call, result)
            } else {
                result.notImplemented()
            }
        }
    }

    private fun startSave(call: MethodCall, result: MethodChannel.Result) {
        if (pendingResult != null) {
            result.error("busy", "Ya hay una operación de guardado activa.", null)
            return
        }

        val files = call.argument<List<Map<String, String>>>("files")
            .orEmpty()
            .mapNotNull { item ->
                val path = item["path"] ?: return@mapNotNull null
                val name = item["name"] ?: return@mapNotNull null
                SaveFile(path, name, item["mimeType"] ?: "application/octet-stream")
            }
            .filter { File(it.path).isFile }

        if (files.isEmpty()) {
            result.error("missing_files", "No hay archivos para guardar.", null)
            return
        }

        pendingResult = result
        pendingFiles = files
        if (files.size == 1) {
            val file = files.first()
            startActivityForResult(
                Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = file.mimeType
                    putExtra(Intent.EXTRA_TITLE, file.name)
                },
                createFileRequest,
            )
        } else {
            startActivityForResult(
                Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                    addFlags(
                        Intent.FLAG_GRANT_READ_URI_PERMISSION or
                            Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                            Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
                    )
                },
                chooseFolderRequest,
            )
        }
    }

    @Deprecated("Required for FlutterActivity compatibility")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != createFileRequest && requestCode != chooseFolderRequest) return

        val result = pendingResult ?: return
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            clearPending()
            result.success(false)
            return
        }

        try {
            if (requestCode == createFileRequest) {
                copyToUri(pendingFiles.first(), uri)
            } else {
                val parent = DocumentsContract.buildDocumentUriUsingTree(
                    uri,
                    DocumentsContract.getTreeDocumentId(uri),
                )
                pendingFiles.forEach { file ->
                    val destination = DocumentsContract.createDocument(
                        contentResolver,
                        parent,
                        file.mimeType,
                        file.name,
                    ) ?: error("No se pudo crear ${file.name}")
                    copyToUri(file, destination)
                }
            }
            clearPending()
            result.success(true)
        } catch (error: Exception) {
            clearPending()
            result.error("save_failed", error.message, null)
        }
    }

    private fun copyToUri(file: SaveFile, destination: Uri) {
        FileInputStream(File(file.path)).use { input ->
            contentResolver.openOutputStream(destination, "w").use { output ->
                requireNotNull(output) { "No se pudo abrir el destino." }
                input.copyTo(output)
            }
        }
    }

    private fun clearPending() {
        pendingResult = null
        pendingFiles = emptyList()
    }
}
