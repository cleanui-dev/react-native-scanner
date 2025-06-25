package com.scanner.views

import android.content.Context
import android.graphics.*
import android.util.AttributeSet
import android.view.View
import com.scanner.FrameSize

// Separate overlay view for frame drawing
class FrameOverlayView : View {
  private var enableFrame: Boolean = false
  private var frameColor: Int = Color.WHITE
  private var frameSize: FrameSize = FrameSize.Square(300)
  var frameRect: RectF? = null
    private set

  constructor(context: Context) : super(context) {
    setWillNotDraw(false)
  }

  constructor(context: Context, attrs: AttributeSet?) : super(context, attrs) {
    setWillNotDraw(false)
  }

  constructor(context: Context, attrs: AttributeSet?, defStyleAttr: Int) : super(context, attrs, defStyleAttr) {
    setWillNotDraw(false)
  }

  override fun onDraw(canvas: Canvas) {
    super.onDraw(canvas)

    if (enableFrame) {
      drawFrame(canvas)
    }
  }

  private fun drawFrame(canvas: Canvas) {
    val centerX = width / 2f
    val centerY = height / 2f

    // Calculate frame dimensions based on frameSize type
    val currentFrameSize = frameSize // Local copy to avoid smart cast issues
    val (frameWidth, frameHeight) = when (currentFrameSize) {
      is FrameSize.Square -> {
        val density = context.resources.displayMetrics.density
        val size = currentFrameSize.size * density
        size to size
      }
      is FrameSize.Rectangle -> {
        val density = context.resources.displayMetrics.density
        val width = currentFrameSize.width * density
        val height = currentFrameSize.height * density
        width to height
      }
    }

    val frameHalfWidth = frameWidth / 2f
    val frameHalfHeight = frameHeight / 2f

    // Calculate frame rectangle
    frameRect = RectF(
      centerX - frameHalfWidth,
      centerY - frameHalfHeight,
      centerX + frameHalfWidth,
      centerY + frameHalfHeight
    )

    // Draw semi-transparent overlay
    val overlayPaint = Paint().apply {
      color = Color.BLACK
      alpha = 128
    }

    // Draw overlay with transparent rectangle
    canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), overlayPaint)

    // Clear the frame area
    val clearPaint = Paint().apply {
      color = Color.TRANSPARENT
      xfermode = PorterDuffXfermode(PorterDuff.Mode.CLEAR)
    }
    canvas.drawRect(frameRect!!, clearPaint)

    // Draw frame border
    val borderPaint = Paint().apply {
      color = frameColor
      style = Paint.Style.STROKE
      strokeWidth = 4f
    }
    canvas.drawRect(frameRect!!, borderPaint)
  }

  fun setEnableFrame(enable: Boolean) {
    enableFrame = enable
    invalidate()
  }

  fun setFrameColor(color: Int) {
    frameColor = color
    invalidate()
  }

  fun setFrameSize(size: FrameSize) {
    frameSize = size
    invalidate()
  }
}