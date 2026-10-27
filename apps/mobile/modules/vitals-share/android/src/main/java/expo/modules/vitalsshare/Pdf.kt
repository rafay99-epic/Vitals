package expo.modules.vitalsshare

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.net.Uri
import android.os.ParcelFileDescriptor
import java.io.File

/** PDF pages for the preview screen, through Android's PdfRenderer. One document stays open; calls are serialized. */
object Pdf {
  /** A tall page is drawn narrower rather than as a huge bitmap. */
  private const val MAX_PIXELS = 12_000_000.0

  private class Open(val path: String, val fd: ParcelFileDescriptor, val renderer: PdfRenderer)

  private var open: Open? = null

  private fun renderer(path: String): PdfRenderer {
    open?.let { if (it.path == path) return it.renderer }
    close()
    val fd = ParcelFileDescriptor.open(File(path), ParcelFileDescriptor.MODE_READ_ONLY)
    val renderer = try {
      PdfRenderer(fd)
    } catch (error: Exception) {
      fd.close()
      throw error
    }
    open = Open(path, fd, renderer)
    return renderer
  }

  /** Each page's height over its width, in order. Its length is the page count. */
  @Synchronized
  fun pages(path: String): DoubleArray {
    val renderer = renderer(path)
    return DoubleArray(renderer.pageCount) { index -> renderer.openPage(index).use { page -> page.height.toDouble() / page.width.coerceAtLeast(1) } }
  }

  /** Page `index` drawn `width` pixels wide on white, as a PNG in the cache. Drawn once per document, page and width. */
  @Synchronized
  fun page(context: Context, path: String, index: Int, width: Int): String {
    val source = File(path)
    val folder = File(context.cacheDir, "vitals-pdf").apply { mkdirs() }
    val out = File(folder, "${Integer.toHexString(path.hashCode())}-${source.lastModified()}-$index-$width.png")
    if (out.isFile) return Uri.fromFile(out).toString()
    val renderer = renderer(path)
    if (index !in 0 until renderer.pageCount) throw IllegalArgumentException("No page ${index + 1}")
    renderer.openPage(index).use { page ->
      val aspect = page.height.toDouble() / page.width.coerceAtLeast(1)
      val wide = minOf(width.toDouble(), Math.sqrt(MAX_PIXELS / aspect)).toInt().coerceAtLeast(1)
      val bitmap = Bitmap.createBitmap(wide, (wide * aspect).toInt().coerceAtLeast(1), Bitmap.Config.ARGB_8888)
      try {
        bitmap.eraseColor(Color.WHITE)
        page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
        val partial = File(folder, "${out.name}.part")
        partial.outputStream().use { stream -> bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream) }
        partial.renameTo(out)
      } finally {
        bitmap.recycle()
      }
    }
    return Uri.fromFile(out).toString()
  }

  @Synchronized
  fun close() {
    open?.let {
      runCatching { it.renderer.close() }
      runCatching { it.fd.close() }
    }
    open = null
  }
}
