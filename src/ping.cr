require "./ping/version"
require "./ping/model"
require "./ping/settings"
require "./ping/history"
require "./ping/history_repository"
require "./ping/icmp_pinger"
require "./ping/chart_renderer"
require "./ping/weekly_chart_renderer"
require "./ping/notifier"
require "./ping/settings_window"
require "./ping/weekly_dashboard_window"
require "./ping/app"

module Ping
  def self.run : Nil
    App.new.run
  end
end

Ping.run
