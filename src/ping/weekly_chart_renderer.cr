module Ping
  class WeeklyChartRenderer
    TICK_RESERVED      = 20.0
    TICK_LABEL_WIDTH   = 40.0
    MINOR_TICK_HEIGHT  = 5.0
    MAJOR_TICK_HEIGHT  = 8.0

    def initialize(
      @settings : Settings,
      @history : HistoryStore,
      @label_font : UIng::FontDescriptor,
      @tick_font : UIng::FontDescriptor,
      @title_font : UIng::FontDescriptor,
      @window_days : Int32,
    )
    end

    def draw(
      params : UIng::Area::Draw::Params,
      current_host : String?,
      snapshot_at : Time,
      range_start_hour : Int32,
      range_end_hour : Int32,
    ) : Nil
      ctx = params.context
      width = params.area_width
      height = params.area_height

      fill_rect(ctx, 0.0, 0.0, width, height, 0.08, 0.10, 0.13)
      draw_text(ctx, chart_title(current_host, snapshot_at, range_start_hour, range_end_hour), 16.0, 10.0, width - 32.0, @title_font, 0.93, 0.95, 0.98)

      plot_left = 116.0
      padding = 8.0
      top = 28.0
      row_gap = 4.0
      row_count = @window_days
      available_height = height - top - padding - row_gap * (row_count - 1)
      return if available_height <= 0

      row_height = available_height / row_count

      plot_width = width - plot_left - padding
      return if plot_width <= 0

      day0_start = start_of_day(snapshot_at)
      window_span = (range_end_hour - range_start_hour).hours
      major_tick_interval, minor_tick_interval = tick_intervals_for(window_span)

      @window_days.times do |index|
        row_top = top + index * (row_height + row_gap)
        day_start = day0_start - index.days
        anchor_time = day_start + range_end_hour.hours
        row_end = index == 0 ? snapshot_at : anchor_time
        fill_until = row_end > anchor_time ? anchor_time : row_end
        row = ChartRow.new(day_label(day_start), window_span, major_tick_interval, minor_tick_interval)

        draw_status_row(ctx, row, row_top, row_height, plot_left, plot_width, anchor_time, fill_until)
      end
    end

    private def draw_status_row(
      ctx : UIng::Area::Draw::Context,
      row : ChartRow,
      row_top : Float64,
      row_height : Float64,
      plot_left : Float64,
      plot_width : Float64,
      anchor_time : Time,
      fill_until : Time,
    ) : Nil
      band_height = row_height - TICK_RESERVED

      fill_rect(ctx, 12.0, row_top, plot_left - 20.0, band_height, 0.13, 0.16, 0.20)
      fill_rect(ctx, plot_left, row_top, plot_width, band_height, 0.12, 0.15, 0.18)

      columns = plot_width.floor.to_i
      columns = 1 if columns < 1
      series = @history.row_series(row.window, columns, anchor_time, fill_until, anchor_time: anchor_time)
      pixel_width = plot_width / columns

      series.states.each_with_index do |severity, index|
        next unless severity

        x = plot_left + pixel_width * index
        w = pixel_width + 0.5
        r, g, b = @settings.color_for(severity)
        fill_rect(ctx, x, row_top + 1.0, w, band_height - 2.0, r, g, b)
      end

      stroke_rect(ctx, plot_left, row_top, plot_width, band_height, 0.30, 0.34, 0.39)
      draw_ticks(ctx, row, row_top, band_height, plot_left, plot_width, anchor_time)
      label_y = row_top + (band_height / 2.0) - 7.0
      draw_text(ctx, row.label, 14.0, label_y, plot_left - 24.0, @label_font, 0.90, 0.92, 0.95)
    end

    private def chart_title(current_host : String?, snapshot_at : Time, range_start_hour : Int32, range_end_hour : Int32) : String
      host = current_host || "no target"
      "Weekly Dashboard  #{host}  #{hour_label(range_start_hour)}-#{hour_label(range_end_hour)}  Snapshot #{snapshot_at.to_s("%m/%d %H:%M")}"
    end

    private def tick_intervals_for(window_span : Time::Span) : {Time::Span, Time::Span}
      span_hours = window_span.total_hours
      major = if span_hours <= 4
                1.hour
              elsif span_hours <= 8
                2.hours
              elsif span_hours <= 12
                3.hours
              else
                6.hours
              end
      minor = span_hours <= 6 ? 30.minutes : 1.hour
      {major, minor}
    end

    private def draw_ticks(
      ctx : UIng::Area::Draw::Context,
      row : ChartRow,
      row_top : Float64,
      band_height : Float64,
      plot_left : Float64,
      plot_width : Float64,
      anchor_time : Time,
    ) : Nil
      return unless window = row.window
      window_start = anchor_time - window
      tick_origin = start_of_day(window_start)
      minor_ticks = aligned_tick_times(window_start, anchor_time, row.minor_tick_interval, tick_origin)
      major_ticks = aligned_tick_times(window_start, anchor_time, row.major_tick_interval, tick_origin)
      labels = label_times(window_start, anchor_time, major_ticks)

      draw_tick_set(ctx, row_top, band_height, plot_left, plot_width, window_start, anchor_time, minor_ticks, MINOR_TICK_HEIGHT, 0.40, 0.44, 0.50, 0.90)
      draw_tick_set(ctx, row_top, band_height, plot_left, plot_width, window_start, anchor_time, major_ticks, MAJOR_TICK_HEIGHT, 0.72, 0.76, 0.82, 1.0)
      draw_tick_labels(ctx, row_top, band_height, plot_left, plot_width, window_start, anchor_time, labels)
    end

    private def draw_tick_labels(
      ctx : UIng::Area::Draw::Context,
      row_top : Float64,
      band_height : Float64,
      plot_left : Float64,
      plot_width : Float64,
      window_start : Time,
      window_end : Time,
      labels : Array(Time),
    ) : Nil
      tick_y = row_top + band_height + 10.0

      labels.each do |label_time|
        x = time_to_x(label_time, window_start, window_end, plot_left, plot_width)
        label_x = (x - TICK_LABEL_WIDTH / 2.0).clamp(plot_left, plot_left + plot_width - TICK_LABEL_WIDTH)
        draw_text(ctx, tick_label(label_time), label_x, tick_y, TICK_LABEL_WIDTH, @tick_font, 0.66, 0.70, 0.76, 0.95)
      end
    end

    private def draw_tick_set(
      ctx : UIng::Area::Draw::Context,
      row_top : Float64,
      band_height : Float64,
      plot_left : Float64,
      plot_width : Float64,
      window_start : Time,
      window_end : Time,
      tick_times : Array(Time),
      tick_height : Float64,
      r : Float64,
      g : Float64,
      b : Float64,
      a : Float64,
    ) : Nil
      tick_y = row_top + band_height + 1.0

      tick_times.each do |tick_time|
        x = time_to_x(tick_time, window_start, window_end, plot_left, plot_width)
        fill_rect(ctx, x, tick_y, 1.0, tick_height, r, g, b, a)
      end
    end

    private def label_times(
      window_start : Time,
      window_end : Time,
      major_ticks : Array(Time),
    ) : Array(Time)
      ticks = [] of Time
      ticks << window_start
      major_ticks.each do |tick_time|
        ticks << tick_time unless ticks.last? == tick_time
      end
      ticks << window_end unless ticks.last? == window_end
      ticks
    end

    private def aligned_tick_times(
      window_start : Time,
      window_end : Time,
      interval : Time::Span,
      tick_origin : Time,
    ) : Array(Time)
      return [] of Time if interval <= Time::Span.zero || window_end <= window_start

      ticks = [] of Time

      interval_seconds = interval.total_seconds
      offset_seconds = (window_start - tick_origin).total_seconds
      first_step = (offset_seconds / interval_seconds).ceil.to_i
      tick_time = tick_origin + interval * first_step
      tick_time += interval if tick_time <= window_start

      while tick_time < window_end
        ticks << tick_time
        tick_time += interval
      end

      ticks
    end

    private def time_to_x(
      time : Time,
      window_start : Time,
      window_end : Time,
      plot_left : Float64,
      plot_width : Float64,
    ) : Float64
      window_seconds = (window_end - window_start).total_seconds
      return plot_left if window_seconds <= 0

      elapsed_seconds = (time - window_start).total_seconds
      fraction = (elapsed_seconds / window_seconds).clamp(0.0, 1.0)
      plot_left + plot_width * fraction
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

    private def start_of_day(time : Time) : Time
      Time.local(time.year, time.month, time.day)
    end

    private def day_label(day_start : Time) : String
      day_start.to_s("%a %m/%d")
    end

    private def tick_label(time : Time) : String
      time.to_s("%H:%M")
    end

    private def hour_label(hour : Int32) : String
      hour.to_s.rjust(2, '0') + ":00"
    end
  end
end
