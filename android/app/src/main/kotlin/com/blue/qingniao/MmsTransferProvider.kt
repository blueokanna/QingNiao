package com.blue.qingniao

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import java.io.File

class MmsTransferProvider : ContentProvider() {
    override fun onCreate() = true
    override fun getType(uri: Uri) = "application/vnd.wap.mms-message"
    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        val name = requireNotNull(uri.lastPathSegment)
        require(name.matches(Regex("[a-f0-9-]{36}\\.pdu")))
        val root = File(requireNotNull(context).filesDir, "mms_transfers").apply { mkdirs() }
        val file = File(root, name)
        return ParcelFileDescriptor.open(file, ParcelFileDescriptor.parseMode(mode))
    }
    override fun query(uri: Uri, projection: Array<out String>?, selection: String?, selectionArgs: Array<out String>?, sortOrder: String?): Cursor? = null
    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?) = 0
    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?) = 0
}
