module Ping
  class ChartRenderer
    TICK_RESERVED = 8.0 # pixels below each band reserved for tick marks

    ROWS = [
      ChartRow.new("24H", 24.hours, 6.hours, 1.hour),
      ChartRow.new("1H", 1.hour, 10.minutes, 1.minute),
      ChartRow.new("10M", 10.minutes, 1.minute, 10.seconds),
      ChartRow.new("1M", 1.minute, 10.seconds, 1.second),
    ] of ChartRow

    def initialize(
      @settings : Settings,
      @history : HistoryStore,
      @label_font : UIng::FontDescriptor,
      @title_font : UIng::FontDescriptor,
    )
    end

    def draw(
      params : UIng::Area::Draw::Params,
      running : Bool,
      current_host : String?,
      interval_ms : Int32,
      stopped_at : Time?,
    ) : Nil
      ctx = params.context
      width = params.area_width
      height = params.area_height

      fill_rect(ctx, 0.0, 0.0, width, height, 0.08, 0.10, 0.13)
      title_alpha = running ? 1.0 : 0.55
      draw_text(ctx, chart_title(running, current_host, interval_ms), 16.0, 10.0, width - 32.0, @title_font, 0.93, 0.95, 0.98, title_alpha)

      plot_left = 72.0
      padding = 14.0
      top = 40.0
      row_gap = 10.0
      row_count = ROWS.size
      available_height = height - top - padding - row_gap * (row_count - 1)
      return if available_height <= 0

      row_height = available_height / row_count

      plot_width = width - plot_left - padding
      return if plot_width <= 0

      now = Time.local
      fill_until = chart_fill_until(now, running, stopped_at)

      ROWS.each_with_index do |row, index|
        row_top = top + index * (row_height + row_gap)

        draw_status_row(ctx, row, row_top, row_height, plot_left, plot_width, now, fill_until)
      end
    end

    private def draw_status_row(
      ctx : UIng::Area::Draw::Context,
      row : ChartRow,
      row_top : Float64,
      row_height : Float64,
      plot_left : Float64,
      plot_width : Float64,
      now : Time,
      fill_until : Time,
    ) : Nil
      band_height = row_height - TICK_RESERVED

      fill_rect(ctx, 12.0, row_top, plot_left - 20.0, band_height, 0.13, 0.16, 0.20)
      fill_rect(ctx, plot_left, row_top, plot_width, band_height, 0.12, 0.15, 0.18)

      columns = plot_width.floor.to_i
      columns = 1 if columns < 1
      series = @history.row_series(row.window, columns, now, fill_until)
      pixel_width = plot_width / columns

      series.states.each_with_index do |severity, index|
        next unless severity

        x = plot_left + pixel_width * index
        w = pixel_width + 0.5
        r, g, b = @settings.color_for(severity)
        fill_rect(ctx, x, row_top + 1.0, w, band_height - 2.0, r, g, b)
      end

      stroke_rect(ctx, plot_left, row_top, plot_width, band_height, 0.30, 0.34, 0.39)
      draw_ticks(ctx, row, row_top, band_height, plot_left, plot_width)
      label_y = row_top + (band_height / 2.0) - 7.0
      draw_text(ctx, row.label, 18.0, label_y, plot_left - 30.0, @label_font, 0.90, 0.92, 0.95)
    end

    private def chart_title(running : Bool, current_host : String?, interval_ms : Int32) : String
      status = running ? "LIVE" : "STOPPED"
      host = current_host || "no target"
      latest = @history.latest_sample

      if latest && latest.success? && (rtt_ms = latest.rtt_ms)
        "#{host}  #{status}  #{interval_ms} ms  RTT #{rtt_ms.round(1)} ms"
      elsif latest && !latest.success?
        "#{host}  #{status}  #{interval_ms} ms  FAIL ×#{latest.failure_streak}"
      else
        "#{host}  #{status}  #{interval_ms} ms"
      end
    end

    private def chart_fill_until(now : Time, running : Bool, stopped_at : Time?) : Time
      return now if running
      stopped_at || @history.latest_sample.try(&.recorded_at) || now
    end

    private def draw_ticks(
      ctx : UIng::Area::Draw::Context,
      row : ChartRow,
      row_top : Float64,
      band_height : Float64,
      plot_left : Float64,
      plot_width : Float64,
    ) : Nil
      return unless window = row.window

      draw_tick_set(ctx, row_top, band_height, plot_left, plot_width, window, row.minor_tick_interval, TICK_RESERVED - 4.0, 0.40, 0.44, 0.50, 0.90)
      draw_tick_set(ctx, row_top, band_height, plot_left, plot_width, window, row.major_tick_interval, TICK_RESERVED - 1.0, 0.72, 0.76, 0.82, 1.0, include_ends: true)
    end

    private def draw_tick_set(
      ctx : UIng::Area::Draw::Context,
      row_top : Float64,
      band_height : Float64,
      plot_left : Float64,
      plot_width : Float64,
      window : Time::Span,
      interval : Time::Span,
      tick_height : Float64,
      r : Float64,
      g : Float64,
      b : Float64,
      a : Float64,
      include_ends : Bool = false,
    ) : Nil
      count = (window.total_seconds / interval.total_seconds).round.to_i
      return if count <= 1

      tick_y = row_top + band_height + 1.0

      start_index = include_ends ? 0 : 1
      end_index = include_ends ? count : count - 1

      start_index.upto(end_index) do |index|
        x = plot_left + plot_width * index.to_f64 / count
        fill_rect(ctx, x, tick_y, 1.0, tick_height, r, g, b, a)
      end
    end

    private def fill_rect(
      ctx : UIng::Area::Draw::Context,
      x : Float64,
      y : Float64,
      width : Float64,
      height : Float64,
      r : Float64,
      g : Float64,
      b : Float64,
      a : Float64 = 1.0,
    ) : Nil
      brush = UIng::Area::Draw::Brush.new(:solid, r, g, b, a)
      ctx.fill_path(brush) do |path|
        path.add_rectangle(x, y, width, height)
      end
    end

    private def stroke_rect(
      ctx : UIng::Area::Draw::Context,
      x : Float64,
      y : Float64,
      width : Float64,
      height : Float64,
      r : Float64,
      g : Float64,
      b : Float64,
    ) : Nil
      brush = UIng::Area::Draw::Brush.new(:solid, r, g, b, 1.0)
      stroke = UIng::Area::Draw::StrokeParams.new(
        cap: :flat,
        join: :miter,
        thickness: 1.0,
        miter_limit: 10.0
      )
      ctx.stroke_path(brush, stroke) do |path|
        path.add_rectangle(x, y, width, height)
      end
    end

    private def draw_text(
      ctx : UIng::Area::Draw::Context,
      text : String,
      x : Float64,
      y : Float64,
      width : Float64,
      font : UIng::FontDescriptor,
      r : Float64,
      g : Float64,
      b : Float64,
      a : Float64 = 1.0,
    ) : Nil
      UIng::Area::AttributedString.open(text) do |attr_str|
        attr_str.set_attribute(UIng::Area::Attribute.new_color(r, g, b, a), 0, attr_str.len)
        UIng::Area::Draw::TextLayout.open(attr_str, font, width) do |layout|
          ctx.draw_text_layout(layout, x, y)
        end
      end
    end
  end
end
