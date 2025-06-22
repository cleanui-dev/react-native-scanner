package com.scanner

import android.graphics.Color
import com.facebook.react.module.annotations.ReactModule
import com.facebook.react.uimanager.SimpleViewManager
import com.facebook.react.uimanager.ThemedReactContext
import com.facebook.react.uimanager.ViewManagerDelegate
import com.facebook.react.uimanager.annotations.ReactProp
import com.facebook.react.viewmanagers.ScannerViewManagerInterface
import com.facebook.react.viewmanagers.ScannerViewManagerDelegate

@ReactModule(name = ScannerViewManager.NAME)
class ScannerViewManager : SimpleViewManager<ScannerView>(),
  ScannerViewManagerInterface<ScannerView> {
  private val mDelegate: ViewManagerDelegate<ScannerView>

  init {
    mDelegate = ScannerViewManagerDelegate(this)
  }

  override fun getDelegate(): ViewManagerDelegate<ScannerView>? {
    return mDelegate
  }

  override fun getName(): String {
    return NAME
  }

  public override fun createViewInstance(context: ThemedReactContext): ScannerView {
    return ScannerView(context)
  }

  @ReactProp(name = "color")
  override fun setColor(view: ScannerView?, color: String?) {
    view?.setBackgroundColor(Color.parseColor(color))
  }

  companion object {
    const val NAME = "ScannerView"
  }
}
