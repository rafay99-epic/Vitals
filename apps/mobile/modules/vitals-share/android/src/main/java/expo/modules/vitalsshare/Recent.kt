package expo.modules.vitalsshare

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.ThumbnailUtils
import android.os.Build
import android.provider.MediaStore
import android.util.Base64
import android.util.Size
import java.io.ByteArrayOutputStream
import java.io.File

/** Newest-first MediaStore pages for a device page: photos, screenshots and documents. */
object Recent {
  private val SHOTS =
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) "(COALESCE(${MediaStore.MediaColumns.RELATIVE_PATH}, '') LIKE '%Screenshots%' OR ${MediaStore.MediaColumns.DATA} LIKE '%/Screenshots/%')"
    else "(${MediaStore.MediaColumns.DATA} LIKE '%/Screenshots/%')"
  private const val MEDIA = "${MediaStore.Files.FileColumns.MEDIA_TYPE} IN (${MediaStore.Files.FileColumns.MEDIA_TYPE_IMAGE}, ${MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO})"

  private val DOC_MIMES = listOf(
    "application/pdf",
    "application/msword",
    "application/vnd.ms-excel",
    "application/vnd.ms-powerpoint",
    "application/rtf",
    "text/rtf",
    "application/epub+zip",
  )
  private val DOC_PREFIXES = listOf("application/vnd.openxmlformats-officedocument.", "application/vnd.oasis.opendocument.")

  private val selections: Map<String, Pair<String, Array<String>>> = mapOf(
    "photos" to ("$MEDIA AND NOT $SHOTS" to emptyArray()),
    "screenshots" to ("$MEDIA AND $SHOTS" to emptyArray()),
    "documents" to (
      "(${MediaStore.MediaColumns.MIME_TYPE} IN (${DOC_MIMES.joinToString(",") { "?" }}) OR ${DOC_PREFIXES.joinToString(" OR ") { "${MediaStore.MediaColumns.MIME_TYPE} LIKE ?" }})" to
        (DOC_MIMES + DOC_PREFIXES.map { "$it%" }).toTypedArray()
      ),
  )

  fun page(context: Context, kind: String, offset: Int, limit: Int): Map<String, Any> {
    val (selection, args) = selections[kind] ?: throw IllegalArgumentException("Unknown kind $kind")
    val columns = arrayOf(MediaStore.MediaColumns.DATA, MediaStore.MediaColumns.DISPLAY_NAME, MediaStore.MediaColumns.SIZE, MediaStore.MediaColumns.DATE_MODIFIED)
    val entries = ArrayList<Map<String, Any>>()
    var more = false
    context.contentResolver.query(MediaStore.Files.getContentUri("external"), columns, selection, args, "${MediaStore.MediaColumns.DATE_MODIFIED} DESC")?.use { cursor ->
      if (offset > 0 && !cursor.moveToPosition(offset - 1)) return@use
      while (cursor.moveToNext()) {
        if (entries.size == limit) {
          more = true
          break
        }
        val path = cursor.getString(0) ?: continue
        val name = cursor.getString(1) ?: path.substringAfterLast('/')
        entries.add(mapOf("path" to path, "name" to name, "size" to cursor.getLong(2).coerceAtLeast(0).toDouble(), "modifiedAt" to (cursor.getLong(3) * 1000).toDouble()))
      }
    }
    return mapOf("entries" to entries, "more" to more)
  }

  private val VIDEO = Regex("\\.(mp4|m4v|mov|mkv|webm|3gp|avi)$", RegexOption.IGNORE_CASE)

  /** A small JPEG of an image or video file, as base64. Null when there is none. */
  fun thumbnail(path: String, px: Int): String? {
    val file = File(path)
    if (!file.isFile) return null
    val bitmap = runCatching { if (VIDEO.containsMatchIn(path)) video(file, px) else image(file, px) }.getOrNull() ?: return null
    val out = ByteArrayOutputStream()
    bitmap.compress(Bitmap.CompressFormat.JPEG, 72, out)
    bitmap.recycle()
    return Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP)
  }

  private fun video(file: File, px: Int): Bitmap? =
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) ThumbnailUtils.createVideoThumbnail(file, Size(px, px), null)
    else @Suppress("DEPRECATION") ThumbnailUtils.createVideoThumbnail(file.path, MediaStore.Images.Thumbnails.MINI_KIND)?.let { ThumbnailUtils.extractThumbnail(it, px, px) }

  private fun image(file: File, px: Int): Bitmap? {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) return ThumbnailUtils.createImageThumbnail(file, Size(px, px), null)
    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    BitmapFactory.decodeFile(file.path, bounds)
    var sample = 1
    while (bounds.outWidth / (sample * 2) >= px && bounds.outHeight / (sample * 2) >= px) sample *= 2
    return BitmapFactory.decodeFile(file.path, BitmapFactory.Options().apply { inSampleSize = sample })
  }
}
