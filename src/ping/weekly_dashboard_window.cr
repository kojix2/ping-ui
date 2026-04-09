module Ping
  class WeeklyDashboardWindow
    WINDOW_WIDTH  = 720
    WINDOW_HEIGHT = 500

    @window : UIng::Window?
    @area : UIng::Area?
    @renderer : WeeklyChartRenderer?
    @snapshot_at : Time?
    @snapshot_host : String?

    def initialize(
      @settings : Settings,
      @label_font : UIng::FontDescriptor,
      @title_font : UIng::FontDescriptor,
    )
      @window = nil
      @area = nil
      @renderer = nil
      @snapshot_at = nil
      @snapshot_host = nil
    end

    def open(parent : UIng::Window?, host : String?, history : HistoryStore) : Nil
      if win = @window
        center_on_parent(win, parent)
        win.show
        return
      end

      snapshot_at = Time.local
      snapshot_history = history.snapshot
      @renderer = WeeklyChartRenderer.new(@settings, snapshot_history, @label_font, @title_font)
      @snapshot_at = snapshot_at
      @snapshot_host = host

      win = UIng::Window.new(window_title(host, snapshot_at), WINDOW_WIDTH, WINDOW_HEIGHT, margined: true)
      @window = win

      handler = UIng::Area::Handler.new
      handler.draw do |_, params|
        next unless renderer = @renderer
        next unless current_snapshot = @snapshot_at

        renderer.draw(params, @snapshot_host, current_snapshot)
      end
      handler.mouse_event { |_, _| nil }
      handler.mouse_crossed { |_, _| nil }
      handler.drag_broken { |_| nil }
      handler.key_event { |_, _| false }

      area = UIng::Area.new(handler)
      @area = area
      win.child = area
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
      @renderer = nil
      @snapshot_at = nil
      @snapshot_host = nil
      @window = nil
    end

    private def window_title(host : String?, snapshot_at : Time) : String
      target = host || "no target"
      "Weekly Dashboard - #{target} - #{snapshot_at.to_s("%m/%d %H:%M")}"
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
