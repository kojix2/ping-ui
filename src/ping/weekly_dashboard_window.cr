module Ping
  class WeeklyDashboardWindow
    WINDOW_WIDTH  = 720
    WINDOW_HEIGHT = 500

    @window : UIng::Window?
    @area : UIng::Area?
    @host_label : UIng::Label?
    @renderer : WeeklyChartRenderer?
    @snapshot_at : Time?
    @snapshot_host : String?
    @source_host : String?
    @range_start_hour : Int32
    @range_end_hour : Int32

    def initialize(
      @settings : Settings,
      @label_font : UIng::FontDescriptor,
      @tick_font : UIng::FontDescriptor,
      @title_font : UIng::FontDescriptor,
      @window_days : Int32,
      @history_loader : Proc(String?, HistoryStore),
    )
      @window = nil
      @area = nil
      @host_label = nil
      @renderer = nil
      @snapshot_at = nil
      @snapshot_host = nil
      @source_host = nil
      @range_start_hour = 9
      @range_end_hour = 18
    end

    def open(parent : UIng::Window?, host : String?) : Nil
      @source_host = host

      if win = @window
        refresh_snapshot
        center_on_parent(win, parent)
        win.show
        @area.try(&.queue_redraw_all)
        return
      end

      refresh_snapshot

      snapshot_at = @snapshot_at || Time.local
      win = UIng::Window.new(window_title(@source_host, snapshot_at), WINDOW_WIDTH, WINDOW_HEIGHT, margined: true)
      @window = win

      host_label = UIng::Label.new(host_text(@source_host))
      @host_label = host_label

      start_spinbox = UIng::Spinbox.new(0, 23, @range_start_hour)
      end_spinbox = UIng::Spinbox.new(1, 24, @range_end_hour)

      start_spinbox.on_changed do |value|
        if value >= @range_end_hour
          adjusted_end = (value + 1).clamp(1, 24)
          @range_end_hour = adjusted_end
          end_spinbox.value = adjusted_end
        end
        @range_start_hour = value.clamp(0, 23)
        apply_range_change
      end

      end_spinbox.on_changed do |value|
        if value <= @range_start_hour
          adjusted_start = (value - 1).clamp(0, 23)
          @range_start_hour = adjusted_start
          start_spinbox.value = adjusted_start
        end
        @range_end_hour = value.clamp(1, 24)
        apply_range_change
      end

      refresh_button = UIng::Button.new("Refresh Snapshot")
      refresh_button.on_clicked do
        refresh_snapshot
        @area.try(&.queue_redraw_all)
      end

      toolbar = UIng::Box.new(:horizontal, padded: true)
      toolbar.append(host_label, stretchy: true)
      toolbar.append(UIng::Label.new("Hours"))
      toolbar.append(start_spinbox)
      toolbar.append(UIng::Label.new("to"))
      toolbar.append(end_spinbox)
      toolbar.append(refresh_button)

      handler = UIng::Area::Handler.new
      handler.draw do |_, params|
        next unless renderer = @renderer
        next unless current_snapshot = @snapshot_at

        renderer.draw(params, @snapshot_host, current_snapshot, @range_start_hour, @range_end_hour)
      end
      handler.mouse_event { |_, _| nil }
      handler.mouse_crossed { |_, _| nil }
      handler.drag_broken { |_| nil }
      handler.key_event { |_, _| false }

      area = UIng::Area.new(handler)
      @area = area

      content = UIng::Box.new(:vertical, padded: true)
      content.append(toolbar)
      content.append(area, stretchy: true)

      win.child = content
      center_on_parent(win, parent)

      win.on_content_size_changed do |_, _|
        area.queue_redraw_all
      end
      win.on_closing do
        clear_snapshot
        true
      end
      win.show
    end

    def close : Nil
      return unless win = @window

      clear_snapshot
      win.destroy
    end

    private def clear_snapshot : Nil
      @area = nil
      @host_label = nil
      @renderer = nil
      @snapshot_at = nil
      @snapshot_host = nil
      @source_host = nil
      @window = nil
    end

    private def refresh_snapshot : Nil
      snapshot_at = Time.local
      host = @source_host
      snapshot_history = @history_loader.call(host)
      @renderer = WeeklyChartRenderer.new(@settings, snapshot_history, @label_font, @tick_font, @title_font, @window_days)
      @snapshot_at = snapshot_at
      @snapshot_host = host
      @host_label.try(&.text = host_text(host))
      @window.try(&.title = window_title(host, snapshot_at))
    end

    private def apply_range_change : Nil
      return unless snapshot_at = @snapshot_at

      @window.try(&.title = window_title(@snapshot_host, snapshot_at))
      @area.try(&.queue_redraw_all)
    end

    private def window_title(host : String?, snapshot_at : Time) : String
      target = host || "no target"
      "Weekly Dashboard - #{target} - #{formatted_range} - #{snapshot_at.to_s("%m/%d %H:%M")}"
    end

    private def formatted_range : String
      "#{hour_label(@range_start_hour)}-#{hour_label(@range_end_hour)}"
    end

    private def host_text(host : String?) : String
      "Host: #{host || "no target"}"
    end

    private def hour_label(hour : Int32) : String
      hour.to_s.rjust(2, '0') + ":00"
    end

    private def center_on_parent(win : UIng::Window, parent : UIng::Window?) : Nil
      return unless parent

      parent_x, parent_y = parent.position
      parent_width, parent_height = parent.content_size
      x = parent_x + (parent_width - WINDOW_WIDTH) // 2
      y = parent_y + (parent_height - WINDOW_HEIGHT) // 2
      win.set_position(x, y)
    rescue
      nil
    end
  end
end
