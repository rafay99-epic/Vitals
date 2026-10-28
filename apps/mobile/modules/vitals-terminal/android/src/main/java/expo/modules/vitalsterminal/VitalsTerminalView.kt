package expo.modules.vitalsterminal

import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.text.Editable
import android.text.InputType
import android.text.TextWatcher
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.EditText
import android.widget.FrameLayout
import expo.modules.kotlin.AppContext
import expo.modules.kotlin.viewevent.EventDispatcher
import expo.modules.kotlin.views.ExpoView
import kotlin.math.max

class VitalsTerminalView(context: Context, appContext: AppContext) : ExpoView(context, appContext) {
  private val container = FrameLayout(context)
  private val canvas = TerminalCanvasView(context)
  private val inputView = object : EditText(context) {
    override fun getAutofillType(): Int = View.AUTOFILL_TYPE_NONE
  }
  private val onInput by EventDispatcher()
  private val onResize by EventDispatcher()
  private var handle = 0L
  private var cols = 0
  private var rows = 0
  private var clearing = false
  private var cleaned = false
  private var renderPosted = false
  private val pending = StringBuilder()
  private var background = Color.BLACK
  private var foreground = Color.WHITE
  private var cursor = Color.WHITE
  private var palette = IntArray(0)

  private val render = Runnable {
    renderPosted = false
    snapshot()
  }

  var fontSize: Float = 12f
    set(value) {
      field = value
      canvas.fontSizeSp = value
      inputView.textSize = max(value, 13f)
      emitResize()
    }

  init {
    canvas.fontSizeSp = fontSize
    canvas.onRequestKeyboard = { focusInput() }
    canvas.onScrollRows = { delta ->
      if (handle != 0L) {
        GhosttyBridge.nativeScroll(handle, delta)
        scheduleRender()
      }
    }
    canvas.onCellMetricsChanged = { emitResize() }
    canvas.selectionDelegate = object : TerminalSelectionDelegate {
      override fun selectWordAt(col: Int, row: Int): Boolean {
        if (handle == 0L) return false
        val selected = GhosttyBridge.nativeSelectWordAt(handle, col, row)
        if (selected) snapshot()
        return selected
      }

      override fun extendSelection(anchorCol: Int, anchorRow: Int, col: Int, row: Int) {
        if (handle == 0L) return
        GhosttyBridge.nativeExtendSelection(handle, anchorCol, anchorRow, col, row)
        snapshot()
      }

      override fun selectAll(): Boolean {
        if (handle == 0L) return false
        val selected = GhosttyBridge.nativeSelectAll(handle)
        if (selected) snapshot()
        return selected
      }

      override fun clearSelection() {
        if (handle == 0L) return
        GhosttyBridge.nativeClearSelection(handle)
        snapshot()
      }

      override fun selectionText(): String? =
        if (handle == 0L) null else GhosttyBridge.nativeGetSelectionText(handle)?.let { String(it, Charsets.UTF_8) }
    }
    configureInput()
    container.addView(canvas, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
    container.addView(inputView, FrameLayout.LayoutParams(1, 1))
    addView(container, LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
    applyTheme()
  }

  fun setTheme(backgroundHex: String, foregroundHex: String, cursorHex: String, colors: List<String>) {
    background = parse(backgroundHex, background)
    foreground = parse(foregroundHex, foreground)
    cursor = parse(cursorHex, cursor)
    palette = colors.map { parse(it, foreground) }.toIntArray()
    applyTheme()
  }

  fun feed(data: String) {
    if (data.isEmpty()) return
    if (handle == 0L) {
      pending.append(data)
      return
    }
    respond(GhosttyBridge.nativeFeed(handle, data.toByteArray(Charsets.UTF_8)))
    if (canvas.hasActiveSelection()) {
      GhosttyBridge.nativeClearSelection(handle)
      canvas.resetSelectionState()
    }
    scheduleRender()
  }

  fun reset() {
    pending.setLength(0)
    if (handle == 0L) return
    destroy()
    create()
    snapshot()
  }

  fun scrollToBottom() {
    if (handle == 0L) return
    GhosttyBridge.nativeScrollToBottom(handle)
    scheduleRender()
  }

  fun focusInput() {
    inputView.requestFocus()
    val manager = context.getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
    manager?.showSoftInput(inputView, InputMethodManager.SHOW_IMPLICIT)
  }

  fun blurInput() {
    inputView.clearFocus()
    val manager = context.getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
    manager?.hideSoftInputFromWindow(windowToken, 0)
  }

  override fun onSizeChanged(width: Int, height: Int, oldWidth: Int, oldHeight: Int) {
    super.onSizeChanged(width, height, oldWidth, oldHeight)
    if (width != oldWidth || height != oldHeight) emitResize()
  }

  override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
    super.onMeasure(widthMeasureSpec, heightMeasureSpec)
    container.measure(MeasureSpec.makeMeasureSpec(measuredWidth, MeasureSpec.EXACTLY), MeasureSpec.makeMeasureSpec(measuredHeight, MeasureSpec.EXACTLY))
  }

  override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
    container.layout(0, 0, right - left, bottom - top)
    if (changed) emitResize()
  }

  fun cleanup() {
    if (cleaned) return
    cleaned = true
    removeCallbacks(render)
    inputView.setOnEditorActionListener(null)
    canvas.onScrollRows = null
    canvas.onRequestKeyboard = null
    canvas.onCellMetricsChanged = null
    canvas.selectionDelegate = null
    destroy()
  }

  private fun typed(data: String) {
    onInput(mapOf("data" to data))
    scrollToBottom()
  }

  private fun configureInput() {
    inputView.setSingleLine(true)
    inputView.setTextColor(Color.TRANSPARENT)
    inputView.setHintTextColor(Color.TRANSPARENT)
    inputView.setBackgroundColor(Color.TRANSPARENT)
    inputView.typeface = Typeface.MONOSPACE
    inputView.textSize = max(fontSize, 13f)
    inputView.alpha = 0.01f
    inputView.isFocusableInTouchMode = true
    inputView.imeOptions = EditorInfo.IME_ACTION_SEND or EditorInfo.IME_FLAG_NO_EXTRACT_UI or EditorInfo.IME_FLAG_NO_FULLSCREEN or EditorInfo.IME_FLAG_NO_PERSONALIZED_LEARNING
    inputView.inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD or InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
    inputView.setPadding(0, 0, 0, 0)
    inputView.setOnEditorActionListener { _, actionId, event ->
      val send = actionId == EditorInfo.IME_ACTION_SEND && event?.action != KeyEvent.ACTION_UP
      val enter = event?.keyCode == KeyEvent.KEYCODE_ENTER && event.action == KeyEvent.ACTION_DOWN
      if (send || enter) {
        typed("\r")
        true
      } else {
        false
      }
    }
    inputView.setOnKeyListener { _, keyCode, event ->
      if (event.action != KeyEvent.ACTION_DOWN) return@setOnKeyListener false
      when {
        keyCode == KeyEvent.KEYCODE_DEL -> {
          typed("\u007F")
          true
        }
        event.isCtrlPressed && keyCode in KeyEvent.KEYCODE_A..KeyEvent.KEYCODE_Z -> {
          typed((keyCode - KeyEvent.KEYCODE_A + 1).toChar().toString())
          true
        }
        else -> false
      }
    }
    inputView.addTextChangedListener(
      object : TextWatcher {
        override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) = Unit

        override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {
          if (clearing || s == null || count <= 0) return
          val end = (start + count).coerceAtMost(s.length)
          if (start < end) typed(s.subSequence(start, end).toString())
        }

        override fun afterTextChanged(editable: Editable?) {
          if (clearing || editable.isNullOrEmpty()) return
          clearing = true
          editable.clear()
          clearing = false
        }
      },
    )
  }

  @Suppress("ComplexCondition")
  private fun emitResize() {
    if (width <= 0 || height <= 0 || canvas.width <= 0 || canvas.height <= 0 || cleaned) return
    val nextCols = (canvas.usableWidth() / canvas.cellWidthPx).toInt().coerceIn(2, 400)
    val nextRows = (canvas.usableHeight() / canvas.cellHeightPx).toInt().coerceIn(2, 200)
    if (nextCols == cols && nextRows == rows && handle != 0L) return
    cols = nextCols
    rows = nextRows
    if (handle == 0L) {
      create()
    } else {
      respond(GhosttyBridge.nativeResize(handle, cols, rows, canvas.cellWidthPx.toInt(), canvas.cellHeightPx.toInt()))
    }
    onResize(mapOf("cols" to cols, "rows" to rows))
    snapshot()
  }

  private fun create() {
    if (handle != 0L || cols <= 0 || rows <= 0 || cleaned) return
    handle = GhosttyBridge.nativeCreate(cols, rows, canvas.cellWidthPx.toInt(), canvas.cellHeightPx.toInt(), foreground, background, cursor, palette)
    if (handle != 0L && pending.isNotEmpty()) {
      val data = pending.toString()
      pending.setLength(0)
      feed(data)
    }
  }

  private fun destroy() {
    if (handle == 0L) return
    GhosttyBridge.nativeDestroy(handle)
    handle = 0L
    canvas.resetSelectionState()
  }

  private fun scheduleRender() {
    if (renderPosted) return
    renderPosted = true
    postOnAnimation(render)
  }

  private fun snapshot() {
    if (handle == 0L) return
    TerminalFrame.decode(GhosttyBridge.nativeSnapshot(handle))?.let(canvas::setFrame)
  }

  private fun respond(response: ByteArray) {
    if (response.isNotEmpty()) onInput(mapOf("data" to String(response, Charsets.UTF_8)))
  }

  private fun applyTheme() {
    setBackgroundColor(background)
    container.setBackgroundColor(background)
    canvas.setBackgroundColor(background)
    if (handle == 0L) return
    GhosttyBridge.nativeSetTheme(handle, foreground, background, cursor, palette)
    snapshot()
  }

  private fun parse(value: String, fallback: Int): Int =
    try {
      Color.parseColor(value)
    } catch (_: IllegalArgumentException) {
      fallback
    }
}
