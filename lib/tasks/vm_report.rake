# rake vm:daily_report
#
# Builds and optionally sends the daily performance report.
# See app/models/vm_daily_report.rb for configuration.
#
# Examples:
#   bundle exec rake vm:daily_report
#   bundle exec rake vm:daily_report DATE=2026-09-29
#   bundle exec rake vm:daily_report DRY_RUN=1

namespace :vm do
  desc 'Send (or print) the daily ticket-performance report for the previous day'
  task daily_report: :environment do
    date     = ENV['DATE'] ? Date.parse(ENV['DATE']) : Date.yesterday
    dry_run  = ENV['DRY_RUN'].to_s.match?(/1|true|yes/)
    enabled  = ENV.fetch('VM_DAILY_REPORT_ENABLED', 'false').match?(/1|true|yes/)

    report = VmDailyReport.new(date: date)
    s      = report.stats

    Rails.logger.info(
      "VmDailyReport: date=#{date} created=#{s[:created_total]} " \
      "ai_classified=#{s.dig(:tag_counts, 'ai_classified') || 0} " \
      "recipients=#{report.recipients.join(', ')}"
    )

    if dry_run || !enabled
      puts report.html
      puts "\n[DRY RUN — set VM_DAILY_REPORT_ENABLED=true to deliver]" unless dry_run
    else
      report.deliver!
      Rails.logger.info "VmDailyReport: delivered to #{report.recipients.join(', ')}"
      puts "Report for #{date} delivered to #{report.recipients.join(', ')}"
    end
  end
end
