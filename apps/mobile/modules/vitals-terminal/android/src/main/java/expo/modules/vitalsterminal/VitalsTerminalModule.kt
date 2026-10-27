package expo.modules.vitalsterminal

import expo.modules.kotlin.functions.Queues
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition
import expo.modules.kotlin.records.Field
import expo.modules.kotlin.records.Record

class TerminalTheme : Record {
  @Field val background: String = "#000000"

  @Field val foreground: String = "#ffffff"

  @Field val cursor: String = "#ffffff"

  @Field val palette: List<String> = emptyList()
}

class VitalsTerminalModule : Module() {
  override fun definition() = ModuleDefinition {
    Name("VitalsTerminal")

    View(VitalsTerminalView::class) {
      Prop("fontSize") { view: VitalsTerminalView, size: Double -> view.fontSize = size.toFloat() }

      Prop("theme") { view: VitalsTerminalView, theme: TerminalTheme -> view.setTheme(theme.background, theme.foreground, theme.cursor, theme.palette) }

      Events("onInput", "onResize")

      AsyncFunction("feed") { view: VitalsTerminalView, data: String -> view.feed(data) }.runOnQueue(Queues.MAIN)

      AsyncFunction("reset") { view: VitalsTerminalView -> view.reset() }.runOnQueue(Queues.MAIN)

      AsyncFunction("scrollToBottom") { view: VitalsTerminalView -> view.scrollToBottom() }.runOnQueue(Queues.MAIN)

      AsyncFunction("focus") { view: VitalsTerminalView -> view.focusInput() }.runOnQueue(Queues.MAIN)

      AsyncFunction("blur") { view: VitalsTerminalView -> view.blurInput() }.runOnQueue(Queues.MAIN)

      OnViewDestroys { view: VitalsTerminalView -> view.cleanup() }
    }
  }
}
