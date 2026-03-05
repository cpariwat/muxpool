require "pty"
require "io/console"

class TerminalChannel < ApplicationCable::Channel
  def subscribed
    @session_name = TmuxSession.sanitize_name(params[:session])
    unless @session_name && TmuxSession.exists?(@session_name)
      reject
      return
    end

    stream_from "terminal_#{@session_name}_#{session_id}"
    start_pty
  end

  def unsubscribed
    stop_pty
  end

  def receive(data)
    return unless @pty_writer

    if data["type"] == "input"
      @pty_writer.write(data["data"])
    elsif data["type"] == "resize"
      resize_pty(data["cols"].to_i, data["rows"].to_i)
    end
  rescue IOError, Errno::EIO
    stop_pty
  end

  private

  def start_pty
    stop_pty

    socket_path = TmuxSession.socket_path
    cmd = [ "tmux", "-S", socket_path, "attach-session", "-t", @session_name ]

    @pty_reader, @pty_writer, @pty_pid = PTY.spawn(*cmd)

    @reader_thread = Thread.new do
      begin
        buf = String.new(encoding: Encoding::BINARY)
        while (bytes = @pty_reader.readpartial(4096))
          buf.replace(bytes)
          ActionCable.server.broadcast(
            "terminal_#{@session_name}_#{session_id}",
            { type: "output", data: Base64.strict_encode64(buf) }
          )
        end
      rescue EOFError, IOError, Errno::EIO
        ActionCable.server.broadcast(
          "terminal_#{@session_name}_#{session_id}",
          { type: "disconnect" }
        )
      end
    end
  end

  def stop_pty
    @reader_thread&.kill
    @reader_thread = nil
    @pty_writer&.close rescue nil
    @pty_writer = nil
    @pty_reader&.close rescue nil
    @pty_reader = nil
    if @pty_pid
      Process.kill("TERM", @pty_pid) rescue nil
      Process.wait(@pty_pid) rescue nil
    end
    @pty_pid = nil
  end

  def resize_pty(cols, rows)
    return unless @pty_writer && cols > 0 && rows > 0

    @pty_writer.winsize = [ rows, cols ]
  rescue IOError, Errno::EIO
    # PTY already closed
  end
end
