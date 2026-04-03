module Ping
  class SettingsWindow
    WINDOW_WIDTH  = 420
    WINDOW_HEIGHT = 400

    @window : UIng::Window?

    def initialize(@settings : Settings, @on_applied : Proc(Nil))
      @window = nil
    end

    def open(parent : UIng::Window?) : Nil
      if win = @window
        center_on_parent(win, parent)
        win.show
        return
      end

      s = @settings
      win = UIng::Window.new("Preferences", WINDOW_WIDTH, WINDOW_HEIGHT, margined: true)
      @window = win

      form = UIng::Form.new(padded: true)

      warn_spinbox = UIng::Spinbox.new(1, 10)
      warn_spinbox.value = s.warn_threshold
      alert_spinbox = UIng::Spinbox.new(1, 20)
      alert_spinbox.value = s.alert_threshold
      notify_enabled = UIng::Checkbox.new("Enable system notifications")
      notify_enabled.checked = s.notify_enabled?
      notify_threshold_spinbox = UIng::Spinbox.new(1, 20)
      notify_threshold_spinbox.value = s.notify_failures_threshold

      ok_btn = UIng::ColorButton.new
      warn_btn = UIng::ColorButton.new
      alert_btn = UIng::ColorButton.new
      crit_btn = UIng::ColorButton.new

      ok_r, ok_g, ok_b = s.color_ok
      ok_btn.set_color(ok_r, ok_g, ok_b, 1.0)
      wn_r, wn_g, wn_b = s.color_warn
      warn_btn.set_color(wn_r, wn_g, wn_b, 1.0)
      al_r, al_g, al_b = s.color_alert
      alert_btn.set_color(al_r, al_g, al_b, 1.0)
      cr_r, cr_g, cr_b = s.color_critical
      crit_btn.set_color(cr_r, cr_g, cr_b, 1.0)

      form.append("Warn threshold (failures <=)", warn_spinbox)
      form.append("Alert threshold (failures <=)", alert_spinbox)
      form.append("", notify_enabled)
      form.append("Notify after failures", notify_threshold_spinbox)
      form.append("OK color", ok_btn)
      form.append("Warn color", warn_btn)
      form.append("Alert color", alert_btn)
      form.append("Critical color", crit_btn)

      apply_btn = UIng::Button.new("Apply")
      apply_btn.on_clicked do
        s.warn_threshold = warn_spinbox.value
        s.alert_threshold = alert_spinbox.value
        s.normalize!
        warn_spinbox.value = s.warn_threshold
        alert_spinbox.value = s.alert_threshold

        r, g, b, _ = ok_btn.color
        s.color_ok = {r, g, b}
        r, g, b, _ = warn_btn.color
        s.color_warn = {r, g, b}
        r, g, b, _ = alert_btn.color
        s.color_alert = {r, g, b}
        r, g, b, _ = crit_btn.color
        s.color_critical = {r, g, b}
        s.notify_enabled = notify_enabled.checked?
        s.notify_failures_threshold = notify_threshold_spinbox.value
        s.save

        @on_applied.call
        @window = nil
        win.destroy
      end

      vbox = UIng::Box.new(:vertical, padded: true)
      vbox.append(form, stretchy: true)
      vbox.append(apply_btn)
      win.child = vbox
      center_on_parent(win, parent)

      win.on_closing do
        @window = nil
        true
      end
      win.show
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
