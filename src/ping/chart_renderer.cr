module Ping
  class ChartRenderer
    ROWS = [
      ChartRow.new("ALL", nil),
      ChartRow.new("1H", 1.hour),
      ChartRow.new("10M", 10.minutes),
      ChartRow.new("1M", 1.minute),
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
      draw_text(ctx, chart_title(running, current_host, interval_ms), 16.0, 10.0, width - 32.0, @title_font, 0.93, 0.95, 0.98)

      plot_left = 84.0
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
        draw_row(ctx, row, row_top, row_height, plot_left, plot_width, now, fill_until)
      end
    end

    private def draw_row(
      ctx : UIng::Area::Draw::Context,
      row : ChartRow,
      row_top : Float64,
      row_height : Float64,
      plot_left : Float64,
      plot_width : Float64,
      now : Time,
      fill_until : Time,
    ) : Nil
      fill_rect(ctx, 12.0, row_top, plot_left - 20.0, row_height, 0.13, 0.16, 0.20)
      fill_rect(ctx, plot_left, row_top, plot_width, row_height, 0.12, 0.15, 0.18)

      guide_width = plot_width / 4.0
      1.upto(3) do |guide|
        x = plot_left + guide_width * guide
        fill_rect(ctx, x, row_top, 1.0, row_height, 0.24, 0.27, 0.32)
      end

      columns = plot_width.floor.to_i
      columns = 1 if columns < 1
      series = @history.row_series(row.window, columns, now, fill_until)
      pixel_width = plot_width / columns

      series.states.each_with_index do |severity, index|
        next unless severity

        x = plot_left + pixel_width * index
        w = pixel_width + 0.5
        r, g, b = @settings.color_for(severity)
        fill_rect(ctx, x, row_top + 1.0, w, row_height - 2.0, r, g, b)
      end

      draw_latency_overlay(ctx, series.latency, series.latency_scale_ms, row_top, row_height, plot_left, plot_width)

      stroke_rect(ctx, plot_left, row_top, plot_width, row_height, 0.30, 0.34, 0.39)
      draw_text(ctx, row.label, 18.0, row_top + 9.0, plot_left - 30.0, @label_font, 0.90, 0.92, 0.95)
      draw_text(ctx, row_caption(row), 18.0, row_top + 27.0, plot_left - 30.0, @label_font, 0.55, 0.64, 0.72)
      draw_text(ctx, "p95 #{series.latency_scale_ms.round} ms", plot_left + plot_width - 84.0, row_top + 6.0, 74.0, @label_font, 0.78, 0.82, 0.88, 0.85)
    end

    private def chart_title(running : Bool, current_host : String?, interval_ms : Int32) : String
      status = running ? "LIVE" : "STOPPED"
      host = current_host || "no target"
      latest = @history.latest_sample

      if latest && latest.success && (rtt_ms = latest.rtt_ms)
        "#{host}  #{status}  #{interval_ms} ms  RTT #{rtt_ms.round(2)} ms"
      elsif latest && !latest.success
        "#{host}  #{status}  #{interval_ms} ms  failures #{latest.failure_streak}"
      else
        "#{host}  #{status}  #{interval_ms} ms"
      end
    end

    private def chart_fill_until(now : Time, running : Bool, stopped_at : Time?) : Time
      return now if running
      stopped_at || @history.latest_sample.try(&.recorded_at) || now
    end

    private def row_caption(row : ChartRow) : String
      case row.label
      when "ALL"
        "since launch"
      when "1H"
        "last 60 minutes"
      when "10M"
        "last 10 minutes"
      else
        "last 60 seconds"
      end
    end

    private def draw_latency_overlay(
      ctx : UIng::Area::Draw::Context,
      latency : Array(Float64?),
      scale_ms : Float64,
      row_top : Float64,
      row_height : Float64,
      plot_left : Float64,
      plot_width : Float64,
    ) : Nil
      return if latency.empty?

      pixel_width = plot_width / latency.size
      inner_top = row_top + 2.0
      inner_height = row_height - 4.0
      return if inner_height <= 0

      shadow = UIng::Area::Draw::Brush.new(:solid, 0.08, 0.10, 0.13, 0.90)
      white = UIng::Area::Draw::Brush.new(:solid, 0.98, 0.99, 1.00, 0.95)

      points = [] of {Float64, Float64}
      latency.each_with_index do |rtt, i|
        if rtt
          x = plot_left + pixel_width * i + pixel_width / 2.0
          ratio = (rtt / scale_ms).clamp(0.0, 1.0)
          y = inner_top + inner_height * (1.0 - ratio)
          points << {x, y}
        else
          stroke_latency_segment(ctx, points, shadow, white)
          points.clear
        end
      end
      stroke_latency_segment(ctx, points, shadow, white)
    end

    private def stroke_latency_segment(
      ctx : UIng::Area::Draw::Context,
      points : Array({Float64, Float64}),
      shadow : UIng::Area::Draw::Brush,
      white : UIng::Area::Draw::Brush,
    ) : Nil
      return if points.size < 2

      shadow_stroke = UIng::Area::Draw::StrokeParams.new(cap: :round, join: :round, thickness: 2.6, miter_limit: 10.0)
      line_stroke = UIng::Area::Draw::StrokeParams.new(cap: :round, join: :round, thickness: 1.4, miter_limit: 10.0)

      ctx.stroke_path(shadow, shadow_stroke) do |path|
        x0, y0 = points[0]
        path.new_figure(x0, y0)
        points.each do |x, y|
          path.line_to(x, y)
        end
      end

      ctx.stroke_path(white, line_stroke) do |path|
        x0, y0 = points[0]
        path.new_figure(x0, y0)
        points.each do |x, y|
          path.line_to(x, y)
        end
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
