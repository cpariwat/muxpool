import { Controller } from "@hotwired/stimulus"
import { Terminal } from "@xterm/xterm"
import { FitAddon } from "@xterm/addon-fit"
import { WebLinksAddon } from "@xterm/addon-web-links"
import consumer from "channels/consumer"

export default class extends Controller {
  static targets = ["terminal", "reconnectBtn"]
  static values = { session: String }

  connect() {
    this.idleTimeout = null
    this.idleDelay = 2000
    this.activityState = "idle"
    this.originalTitle = this.sessionValue
    this.tmuxScrollMode = false
    this.scrollExitTimeout = null

    this.setupTerminal()
    this.connectChannel()
    this.setupResize()
    this.updateTitle("idle")
  }

  disconnect() {
    this.clearIdleTimeout()
    this.teardown()
  }

  setupTerminal() {
    if (this.term) {
      this.term.dispose()
      this.term = null
    }

    this.term = new Terminal({
      cursorBlink: true,
      fontSize: 14,
      fontFamily: "'JetBrains Mono', 'Fira Code', 'SF Mono', Monaco, 'Cascadia Code', 'Roboto Mono', Menlo, monospace",
      theme: {
        background: "#0d1117",
        foreground: "#c9d1d9",
        cursor: "#58a6ff",
        selectionBackground: "#264f78",
        black: "#0d1117",
        red: "#ff7b72",
        green: "#3fb950",
        yellow: "#d29922",
        blue: "#58a6ff",
        magenta: "#bc8cff",
        cyan: "#39d2c0",
        white: "#c9d1d9",
        brightBlack: "#484f58",
        brightRed: "#ffa198",
        brightGreen: "#56d364",
        brightYellow: "#e3b341",
        brightBlue: "#79c0ff",
        brightMagenta: "#d2a8ff",
        brightCyan: "#56d4dd",
        brightWhite: "#f0f6fc",
      },
      allowProposedApi: true,
      scrollback: 10000,
    })

    this.fitAddon = new FitAddon()
    this.term.loadAddon(this.fitAddon)
    this.term.loadAddon(new WebLinksAddon())

    this.term.open(this.terminalTarget)
    this.fitAddon.fit()

    this.term.onData((data) => {
      if (this.channel) {
        if (this.tmuxScrollMode) {
          this.exitTmuxScrollMode()
        }
        this.channel.send({ type: "input", data: data })
      }
    })

    // Capture wheel events before xterm.js's canvas gets them
    this.handleWheelBound = this.handleWheel.bind(this)
    this.terminalTarget.addEventListener("wheel", this.handleWheelBound, { capture: true })

    this.term.onResize(({ cols, rows }) => {
      if (this.channel) {
        this.channel.send({ type: "resize", cols: cols, rows: rows })
      }
    })
  }

  connectChannel() {
    if (this.channel) {
      this.channel.unsubscribe()
      this.channel = null
    }

    const sessionName = this.sessionValue

    this.channel = consumer.subscriptions.create(
      { channel: "TerminalChannel", session: sessionName },
      {
        connected: () => {
          this.term.clear()
          // Send initial size
          const dims = this.fitAddon.proposeDimensions()
          if (dims) {
            this.channel.send({ type: "resize", cols: dims.cols, rows: dims.rows })
          }
        },
        disconnected: () => {
          this.term.write("\r\n\x1b[33m--- Disconnected ---\x1b[0m\r\n")
        },
        received: (data) => {
          if (data.type === "output") {
            const bytes = Uint8Array.from(atob(data.data), c => c.charCodeAt(0))
            this.term.write(bytes)
            this.markWorking()
          } else if (data.type === "disconnect") {
            this.term.write("\r\n\x1b[31m--- Session ended ---\x1b[0m\r\n")
            this.updateTitle("disconnected")
          }
        },
      }
    )
  }

  setupResize() {
    this.resizeObserver = new ResizeObserver(() => {
      this.fitAddon.fit()
    })
    this.resizeObserver.observe(this.terminalTarget)
  }

  scrollMode() {
    if (this.channel) {
      this.channel.send({ type: "scroll", direction: "up", lines: 0 })
      this.tmuxScrollMode = true
    }
    this.focusTerminal()
  }

  scrollUp() {
    if (this.channel) {
      this.tmuxScrollMode = true
      this.channel.send({ type: "scroll", direction: "up", lines: this.term.rows })
    }
  }

  scrollDown() {
    if (this.channel) {
      this.channel.send({ type: "scroll", direction: "down", lines: this.term.rows })
    }
  }

  exitScroll() {
    this.exitTmuxScrollMode()
    this.focusTerminal()
  }

  handleWheel(event) {
    event.preventDefault()
    event.stopPropagation()
    if (!this.channel) return

    // Accumulate sub-line deltas from trackpad
    this.scrollAccumulator = (this.scrollAccumulator || 0) + event.deltaY
    const threshold = 30
    const lines = Math.trunc(this.scrollAccumulator / threshold)
    if (lines === 0) return
    this.scrollAccumulator -= lines * threshold

    if (lines < 0) {
      this.tmuxScrollMode = true
      this.channel.send({ type: "scroll", direction: "up", lines: Math.min(Math.abs(lines), 10) })
    } else if (this.tmuxScrollMode) {
      this.channel.send({ type: "scroll", direction: "down", lines: Math.min(lines, 10) })
    }

    this.resetScrollExitTimer()
  }

  resetScrollExitTimer() {
    if (this.scrollExitTimeout) {
      clearTimeout(this.scrollExitTimeout)
    }
    this.scrollExitTimeout = setTimeout(() => {
      this.exitTmuxScrollMode()
    }, 3000)
  }

  exitTmuxScrollMode() {
    if (this.scrollExitTimeout) {
      clearTimeout(this.scrollExitTimeout)
      this.scrollExitTimeout = null
    }
    if (this.tmuxScrollMode && this.channel) {
      this.channel.send({ type: "scroll_exit" })
      this.tmuxScrollMode = false
    }
  }

  splitHorizontal() {
    this.sendTmuxKey('"')
  }

  splitVertical() {
    this.sendTmuxKey('%')
  }

  nextPane() {
    this.sendTmuxKey('o')
  }

  closePane() {
    this.sendTmuxKey('x')
  }

  zoomPane() {
    this.sendTmuxKey('z')
  }

  sendTmuxKey(key) {
    if (this.channel) {
      this.channel.send({ type: "input", data: `\x02${key}` })
    }
    this.focusTerminal()
  }

  async paste() {
    try {
      const text = await navigator.clipboard.readText()
      if (text && this.channel) {
        this.channel.send({ type: "input", data: text })
      }
    } catch {
      // Clipboard API denied — fallback not available on mobile
    }
    this.focusTerminal()
  }

  reconnect() {
    if (this.channel) {
      this.channel.unsubscribe()
    }
    this.term.clear()
    this.term.write("\x1b[33mReconnecting...\x1b[0m\r\n")
    this.connectChannel()
  }

  markWorking() {
    if (this.activityState !== "working") {
      this.activityState = "working"
      this.updateTitle("working")
    }
    this.clearIdleTimeout()
    this.idleTimeout = setTimeout(() => {
      this.activityState = "idle"
      this.updateTitle("idle")
    }, this.idleDelay)
  }

  clearIdleTimeout() {
    if (this.idleTimeout) {
      clearTimeout(this.idleTimeout)
      this.idleTimeout = null
    }
  }

  updateTitle(state) {
    const name = this.originalTitle
    const appName = document.querySelector('meta[name="app-name"]')?.content || "Terminal"
    switch (state) {
      case "working":
        document.title = `\u25B6 ${name} - ${appName}`
        break
      case "idle":
        document.title = `\u23F8 ${name} - ${appName}`
        break
      case "disconnected":
        document.title = `\u23F9 ${name} - ${appName}`
        break
    }
  }

  preventFocus(event) {
    event.preventDefault()
  }

  focusTerminal() {
    requestAnimationFrame(() => this.term?.focus())
  }

  teardown() {
    if (this.scrollExitTimeout) {
      clearTimeout(this.scrollExitTimeout)
      this.scrollExitTimeout = null
    }
    this.tmuxScrollMode = false
    if (this.handleWheelBound) {
      this.terminalTarget.removeEventListener("wheel", this.handleWheelBound, { capture: true })
    }
    this.resizeObserver?.disconnect()
    if (this.channel) {
      this.channel.unsubscribe()
      this.channel = null
    }
    this.term?.dispose()
  }
}
