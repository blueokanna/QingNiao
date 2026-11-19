package com.blue.qingniao

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import java.io.FileNotFoundException

/** Exposes one verified private APK, read-only and only under a temporary URI grant. */
class AppUpdateProvider : ContentProvider() {
    override fun onCreate() = true
    private fun file(uri: Uri): java.io.File {
        val app = requireNotNull(context)
        if (uri.authority != "${app.packageName}.updates" || uri.path != "/qingniao-update.apk" ||
            uri.query != null || uri.fragment != null) throw FileNotFoundException()
        return AppUpdates.readyFile(app)
    }
    override fun getType(uri: Uri): String {
        file(uri)
        return "application/vnd.android.package-archive"
    }
    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        if (mode != "r") throw FileNotFoundException("Read-only update")
        return ParcelFileDescriptor.open(file(uri), ParcelFileDescriptor.MODE_READ_ONLY)
    }
    override fun query(uri: Uri, projection: Array<out String>?, selection: String?,
        selectionArgs: Array<out String>?, sortOrder: String?): Cursor {
        val apk = file(uri)
        val columns = projection ?: arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE)
        return MatrixCursor(columns).apply {
            addRow(columns.map {
                when (it) {
                    OpenableColumns.DISPLAY_NAME -> apk.name
                    OpenableColumns.SIZE -> apk.length()
                    else -> null
                }
            })
        }
    }
    override fun insert(uri: Uri, values: ContentValues?): Uri? = throw UnsupportedOperationException()
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = throw UnsupportedOperationException()
    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?): Int = throw UnsupportedOperationException()
}
