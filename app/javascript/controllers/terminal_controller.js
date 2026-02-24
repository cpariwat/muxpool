import { Controller } from "@hotwired/stimulus"
import { Terminal } from "@xterm/xterm"
import { FitAddon } from "@xterm/addon-fit"
import { WebLinksAddon } from "@xterm/addon-web-links"
import consumer from "../channels/consumer"

export default class extends Controller {
  static targets = ["terminal", "reconnectBtn"]
  static values = { session: String }

  connect() {
    this.setupTerminal()
    this.connectChannel()
    this.setupResize()
  }

  disconnect() {
    this.teardown()
  }

  setupTerminal() {
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
        this.channel.send({ type: "input", data: data })
      }
    })

    this.term.onResize(({ cols, rows }) => {
      if (this.channel) {
        this.channel.send({ type: "resize", cols: cols, rows: rows })
      }
    })
  }

  connectChannel() {
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
          } else if (data.type === "disconnect") {
            this.term.write("\r\n\x1b[31m--- Session ended ---\x1b[0m\r\n")
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

  reconnect() {
    if (this.channel) {
      this.channel.unsubscribe()
    }
    this.term.clear()
    this.term.write("\x1b[33mReconnecting...\x1b[0m\r\n")
    this.connectChannel()
  }

  teardown() {
    this.resizeObserver?.disconnect()
    if (this.channel) {
      this.channel.unsubscribe()
      this.channel = null
    }
    this.term?.dispose()
  }
}
