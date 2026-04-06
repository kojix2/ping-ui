require "random/secure"
require "uing"

module Ping
  class App
    WINDOW_TITLE       = "Ping Activity Monitor"
    WINDOW_WIDTH       = 450
    WINDOW_HEIGHT      = 600
    CONSOLE_LINE_LIMIT = 800

    @settings : Settings
    @window : UIng::Window?
    @combo : UIng::EditableCombobox?
    @interval_spinbox : UIng::Spinbox?
    @toggle_button : UIng::Button?
    @console : UIng::MultilineEntry?
    @area : UIng::Area?
    @start_item : UIng::MenuItem?
    @stop_item : UIng::MenuItem?
    @settings_window : SettingsWindow
    @renderer : ChartRenderer
    @notifier : Notifier
    @history_repository : HistoryRepository?
    @pinger : ICMPPinger?
    @history : HistoryStore
    @console_lines = [] of String
    @instance_id : String
    @current_session_id : Int64?
    @next_local_session_id : Int64
    @current_host : String? = nil
    @running = false
    @stopped_at : Time? = nil
    @stop_redraw_running = false
    @shutting_down = false
    @label_font : UIng::FontDescriptor
    @title_font : UIng::FontDescriptor

    def initialize
      @settings = Settings.load
      @history = HistoryStore.new(@settings)
      @history_repository = nil
      @instance_id = "#{Process.pid}-#{Random::Secure.hex(8)}"
      @current_session_id = nil
      @next_local_session_id = -1_i64
      font_family = default_font_family
      @label_font = UIng::FontDescriptor.new(
        family: font_family,
        size: 12,
        weight: :normal,
        italic: :normal,
        stretch: :normal
      )
      @title_font = UIng::FontDescriptor.new(
        family: font_family,
        size: 13,
        weight: :bold,
        italic: :normal,
        stretch: :normal
      )
      @renderer = ChartRenderer.new(@settings, @history, @label_font, @title_font)
      @notifier = Notifier.new(@settings)
      @settings_window = SettingsWindow.new(@settings, -> {
        @area.try(&.queue_redraw_all)
      })
    end

    def run : Nil
      UIng.init
      build_settings_menu
      build_ui
      if window = @window
        window.show
      end
      UIng.main
    ensure
      shutdown
      @label_font.free
      @title_font.free
      UIng.uninit
    end

    private def build_settings_menu : Nil
      UIng::Menu.new("File") do
        @start_item = append_item("Start Monitoring")
        @start_item.try(&.on_clicked { |_| start_monitoring })
        @stop_item = append_item("Stop Monitoring")
        @stop_item.try(&.on_clicked { |_| stop_monitoring })
        @stop_item.try(&.disable)
        append_separator
        append_item("Save Log...").on_clicked { |_| save_log }
        append_separator
        append_quit_item
      end

      UIng::Menu.new("Help") do
        append_preferences_item.on_clicked do |_|
          @settings_window.open(@window)
        end
        append_about_item.on_clicked do |window|
          window.msg_box(
            "About Ping UI",
            "Ping UI v#{VERSION}\nA ping activity monitor built with Crystal and UIng."
          )
        end
      end
    end

    private def build_ui : Nil
      window = UIng::Window.new(WINDOW_TITLE, WINDOW_WIDTH, WINDOW_HEIGHT, menubar: true, margined: true)
      combo = UIng::EditableCombobox.new(@settings.recent_hosts)
      combo.text = @settings.recent_hosts.first? || "8.8.8.8"
      interval_spinbox = UIng::Spinbox.new(Settings::MIN_INTERVAL_MS, Settings::MAX_INTERVAL_MS)
      interval_label = UIng::Label.new("ms")
      interval_spinbox.value = Settings::DEFAULT_INTERVAL_MS

      toggle_button = UIng::Button.new("GO")

      toolbar = UIng::Box.new(:horizontal, padded: true)
      toolbar.append(combo, stretchy: true)
      toolbar.append(interval_spinbox)
      toolbar.append(interval_label)
      toolbar.append(toggle_button)

      handler = UIng::Area::Handler.new
      handler.draw do |_, params|
        @renderer.draw(params, @running, @current_host, interval_ms, @stopped_at)
      end
      handler.mouse_event { |_, _| nil }
      handler.mouse_crossed { |_, _| nil }
      handler.drag_broken { |_| nil }
      handler.key_event { |_, _| false }

      area = UIng::Area.new(handler)
      console = UIng::MultilineEntry.new(wrapping: false, read_only: true)
      console.text = "Ping monitor ready. Enter a host or IP, then press GO.\n"

      content = UIng::Box.new(:vertical, padded: true)
      content.append(area, stretchy: true)
      content.append(console, stretchy: true)

      root = UIng::Box.new(:vertical, padded: true)
      root.append(toolbar)
      root.append(content, stretchy: true)

      toggle_button.on_clicked do
        if @running
          stop_monitoring
        else
          start_monitoring
        end
      end

      window.child = root
      window.on_content_size_changed do |_, _|
        area.queue_redraw_all
      end
      window.on_closing do
        stop_monitoring
        UIng.quit
        true
      end
      UIng.on_should_quit do
        window.destroy # You have to destroy the window manually.
        true           # UIng.quit is automatically called in the C function onQuitClicked().
      end

      @window = window
      @combo = combo
      @interval_spinbox = interval_spinbox
      @toggle_button = toggle_button
      @console = console
      @area = area
    end

    private def start_monitoring : Nil
      host = @combo.try(&.text).to_s.strip
      if host.empty?
        @window.try(&.msg_box_error("Missing target", "Enter an IP address or host name."))
        return
      end

      new_host = !@settings.recent_hosts.includes?(host)
      @settings.add_recent_host(host)
      @combo.try(&.append(host)) if new_host

      if @current_host && @current_host != host
        @history.clear
        @console_lines.clear
        @console.try(&.text = "")
      end

      should_load_history = @current_host != host || @history.samples.empty?
      load_history_for_host(host) if should_load_history

      started_at = Time.local
      session = begin_session(host, started_at)

      @pinger.try(&.stop)
      @pinger = ICMPPinger.new(
        ->(line : String) { enqueue_log(line) },
        ->(input : SampleInput) { enqueue_sample(input) },
        ->(message : String?) { enqueue_finish(message) },
        interval_span
      )

      @current_host = host
      @current_session_id = session.id
      @history.start_session(session)
      @notifier.reset
      @running = true
      @stopped_at = nil
      update_buttons
      append_console("starting ping for #{host} every #{interval_ms} ms")
      @area.try(&.queue_redraw_all)
      @pinger.try(&.start(host))
    rescue ex
      end_current_session(Time.local)
      append_console("failed to start ping: #{ex.message}")
      @running = false
      @pinger = nil
      update_buttons
    end

    private def stop_monitoring : Nil
      return unless @running || @pinger

      stopped_at = Time.local
      append_console("stopping ping") if @running
      @running = false
      @stopped_at = stopped_at
      end_current_session(stopped_at)
      @pinger.try(&.stop)
      update_buttons
      @area.try(&.queue_redraw_all)
      start_stop_redraw_timer
    end

    private def start_stop_redraw_timer : Nil
      return if @stop_redraw_running

      @stop_redraw_running = true
      schedule_stop_redraw_tick(interval_ms)
    end

    private def schedule_stop_redraw_tick(delay_ms : Int32) : Nil
      UIng.timer(delay_ms) do
        if @running || @shutting_down
          @stop_redraw_running = false
        else
          @area.try(&.queue_redraw_all)
          schedule_stop_redraw_tick(interval_ms)
        end
        0_i32
      end
    end

    private def enqueue_log(line : String) : Nil
      UIng.queue_main do
        append_console(line)
      end
    end

    private def enqueue_sample(input : SampleInput) : Nil
      UIng.queue_main do
        if session_id = @current_session_id
          sample = @history.add(input, session_id)
          persist_sample(session_id, sample)
          if host = @current_host
            @notifier.maybe_notify(host, sample)
          end
        else
          append_console("ignoring sample without monitoring session")
        end
        @area.try(&.queue_redraw_all)
      end
    end

    private def enqueue_finish(message : String?) : Nil
      UIng.queue_main do
        @pinger = nil
        @running = false
        stopped_at = @stopped_at || Time.local
        @stopped_at = stopped_at
        end_current_session(stopped_at)
        append_console(message) if message
        update_buttons
        @area.try(&.queue_redraw_all)
      end
    end

    private def update_buttons : Nil
      if @running
        @combo.try(&.disable)
        @interval_spinbox.try(&.disable)
        @toggle_button.try(&.text = "STOP")
        @start_item.try(&.disable)
        @stop_item.try(&.enable)
      else
        @combo.try(&.enable)
        @interval_spinbox.try(&.enable)
        @toggle_button.try(&.text = "GO")
        @start_item.try(&.enable)
        @stop_item.try(&.disable)
      end
    end

    private def append_console(line : String?) : Nil
      return unless line

      stamp = Time.local.to_s("%H:%M:%S")
      @console_lines.unshift("[#{stamp}] #{line}")
      @console_lines.pop(@console_lines.size - CONSOLE_LINE_LIMIT) if @console_lines.size > CONSOLE_LINE_LIMIT
      @console.try(&.text = @console_lines.join("\n") + "\n")
    end

    private def interval_ms : Int32
      spinbox = @interval_spinbox
      value = spinbox ? spinbox.value : Settings::DEFAULT_INTERVAL_MS
      @settings.clamp_interval_ms(value)
    end

    private def interval_span : Time::Span
      interval_ms.milliseconds
    end

    private def shutdown : Nil
      @shutting_down = true
      @stop_redraw_running = false
      end_current_session(Time.local)
      @pinger.try(&.stop)
      @pinger = nil
      @history_repository.try(&.close)
      @history_repository = nil
    end

    private def repository : HistoryRepository?
      repo = @history_repository
      return repo if repo

      @history_repository = HistoryRepository.new
    rescue ex
      append_console("history database unavailable: #{ex.message}")
      nil
    end

    private def begin_session(host : String, started_at : Time) : MonitoringSession
      repo = repository
      return build_local_session(host, started_at) unless repo

      repo.create_session(host, @instance_id, started_at)
    rescue ex
      append_console("failed to create monitoring session: #{ex.message}")
      build_local_session(host, started_at)
    end

    private def end_current_session(ended_at : Time) : Nil
      session_id = @current_session_id
      return unless session_id

      @history.finish_session(session_id, ended_at)
      if session_id > 0
        begin
          repository.try(&.close_session(session_id, ended_at))
        rescue ex
          append_console("failed to close monitoring session: #{ex.message}")
        end
      end

      @current_session_id = nil
    end

    private def build_local_session(host : String, started_at : Time) : MonitoringSession
      session_id = @next_local_session_id
      @next_local_session_id -= 1
      MonitoringSession.new(session_id, host, @instance_id, started_at, nil)
    end

    private def persist_sample(session_id : Int64, sample : Sample) : Nil
      repo = repository
      return unless repo

      repo.save_sample(session_id, sample)
    rescue ex
      append_console("failed to save sample: #{ex.message}")
    end

    private def load_history_for_host(host : String) : Nil
      repo = repository
      return unless repo

      since = Time.local - 24.hours
      sessions, samples = repo.load_history(host, since)
      @history.replace(sessions, samples)
    rescue ex
      append_console("failed to load history: #{ex.message}")
    end

    private def default_font_family : String
      {% if flag?(:darwin) %}
        "Menlo"
      {% elsif flag?(:linux) %}
        "Monospace"
      {% elsif flag?(:win32) %}
        "Consolas"
      {% else %}
        "Sans"
      {% end %}
    end

    private def save_log : Nil
      if @console_lines.empty?
        @window.try(&.msg_box("Save Log", "No log entries to save."))
        return
      end

      path = @window.try(&.save_file)
      return unless path

      begin
        File.write(path, @console_lines.reverse.join("\n") + "\n")
      rescue ex
        @window.try(&.msg_box_error("Save failed", ex.message || "Unknown error"))
      end
    end
  end
end
