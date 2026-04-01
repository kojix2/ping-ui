module Ping
  class SettingsWindow
    @window : UIng::Window?

    def initialize(@settings : Settings, @on_applied : Proc(Nil))
      @window = nil
    end

    def open : Nil
      if win = @window
        win.show
        return
      end

      s = @settings
      win = UIng::Window.new("Preferences", 380, 340, margined: true)
      @window = win

      form = UIng::Form.new(padded: true)

      warn_spinbox = UIng::Spinbox.new(1, 10)
      warn_spinbox.value = s.warn_threshold
      alert_spinbox = UIng::Spinbox.new(1, 20)
      alert_spinbox.value = s.alert_threshold

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

      form.append("Yellow threshold (streak <=)", warn_spinbox)
      form.append("Orange threshold (streak <=)", alert_spinbox)
      form.append("Green (ok)", ok_btn)
      form.append("Yellow (warn)", warn_btn)
      form.append("Orange (alert)", alert_btn)
      form.append("Red (critical)", crit_btn)

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

        @on_applied.call
        @window = nil
        win.destroy
      end

      vbox = UIng::Box.new(:vertical, padded: true)
      vbox.append(form, stretchy: true)
      vbox.append(apply_btn)
      win.child = vbox

      win.on_closing do
        @window = nil
        true
      end
      win.show
    end
  end
end
