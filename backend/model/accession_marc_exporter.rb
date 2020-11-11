require 'mail'
require 'stringio'
require 'set'
require 'tempfile'
require 'date'
require 'time'

require_relative 'pending_payments'

class AccessionMarcExporter

  MAX_RETRIES = 10
  RETRY_WAIT = 5 * 60

  def self.run!
    Log.info("AccessionMarcExporter is off to the races!")

    exporter = self.new
    MAX_RETRIES.times.each do |i|
      begin
        exporter.run_round!
        exporter.upload_log!("success")

        return
      rescue
        exporter.log(80.times.map{'!'}.join)
        exporter.log("Error running round: #{$!.message}")
        exporter.log($!.backtrace.join("\n"))

        if i == MAX_RETRIES - 1
          exporter.log("\n\nTried #{MAX_RETRIES} times. Giving up for the day.")
          exporter.upload_log!("errored")
          return
        end

        sleep RETRY_WAIT
      end
    end
  end

  def upload_log!(overall_status)
    @log ||= StringIO.new
    content = @log.string

    Tempfile.create('export_log') do |temp|
      temp.puts "#{Date.today} Overall job status: #{overall_status}\n\n"
      temp.puts content.strip
      temp.flush

      upload_file(temp.path, "job_status-#{Date.today.iso8601}-#{Time.now.strftime('%H%M%S')}.txt")
    end

    @log.truncate(0)
  end

  def run_round!
    log("%s\n%s\n%s" % [
          80.times.map{'*'}.join,
          "Running round at #{Time.now}",
          80.times.map{'*'}.join
        ])

    today = Date.today

    DB.open(false) do |db|
      payments_to_process = PendingPayments.new(db, today, proc {|msg| log(msg)})

      if payments_to_process.empty?
        log("No payments to process")
        return
      end

      exports_by_vendor = {}

      log("\nConverting payments to MARC\n===========================")

      log_indent do
        payments_to_process.each do |accession, vendor_code, payment|
          exports_by_vendor[vendor_code] ||= {
            :marc => AccessionMARCExport.new(vendor_code, today),
            :payments => [],
            :failed => false,
          }

          export = exports_by_vendor.fetch(vendor_code)
          unless export[:failed]
            begin
              export[:marc].add_payment(accession, payment)
              export[:payments] << payment

              log("Converted payment for vendor #{vendor_code}")
            rescue
              log("Error caught during process for vendor #{vendor_code}\nPayment #{payment.pretty_inspect}: #{$!}")
              export[:failed] = $!
            end
          end
        end
      end

      log("\nUploading MARC records and marking payments as processed\n========================================================")

      log_indent do
        exports_by_vendor.each do |vendor_code, export|
          next if export[:failed]

          DB.open do |db|
            begin
              upload_marc_export(export[:marc])
              mark_payments_as_processed(db, export[:payments], today)

              log("Processed #{export[:payments].length} #{pluralize('payment', '', 's', export[:payments].length)} for vendor #{vendor_code}")
            ensure
              export[:marc].finished!
            end
          end
        end
      end

      if (failure = exports_by_vendor.values.find {|export| export[:failed]})
        # Throw an exception to trigger a retry for this vendor.
        raise failure[:failed]
      end
    end

    log("%s\n%s\n%s" % [
          80.times.map{'*'}.join,
          "Finished round at #{Time.now}",
          80.times.map{'*'}.join
        ])
  end

  def log_indent(&block)
    @log_indent ||= 0
    @log_indent += 2
    begin
      block.call
    ensure
      @log_indent -= 2
    end
  end

  def log(message)
    indent_str = (" " * (@log_indent || 0))

    @log ||= StringIO.new
    @log << "\n"
    @log << indent_str + message.to_s.gsub("\n", "\n#{indent_str}")
    @log << "\n"

    Log.info("%s: %s" % ['AccessionMarcExporter', message])
  end

  private

  def pluralize(word, drop, add, count = 1)
    return word if count == 1

    word.gsub(/#{drop}$/, add)
  end

  def mark_payments_as_processed(db, payments, today)
    now = Time.now

    db[:payment]
      .filter(:id => payments.map(&:payment_id))
      .update(:date_paid => today)

    db[:accession]
      .filter(:id => payments.map(&:accession_id))
      .update(:lock_version => Sequel.expr(1) + :lock_version,
              :system_mtime => now,
              :user_mtime => now,
              :last_modified_by => 'AccessionMarcExporter')
  end


  def upload_marc_export(marc)
    upload_file(marc.file.path, marc.filename)
  end

  def upload_file(source_path, remote_target_file)
    if AppConfig[:yale_accession_marc_export_target].to_s == 's3'
      log("Uploading file #{remote_target_file} to S3")
      @aws_uploader ||= AWSUploader.new
      @aws_uploader.upload!(remote_target_file, source_path)

    elsif AppConfig[:yale_accession_marc_export_target].to_s == 'sftp'
      log("Uploading file #{remote_target_file} to SFTP")
      @sftp_uploader ||= SFTPUploader.new
      @sftp_uploader.upload!(remote_target_file, source_path)

    elsif AppConfig[:yale_accession_marc_export_target].to_s == 'local'
      log("Storing file #{remote_target_file} locally at #{AppConfig[:yale_accession_marc_export_path]}")
      unless File.directory?(AppConfig[:yale_accession_marc_export_path])
        FileUtils.mkdir_p(AppConfig[:yale_accession_marc_export_path])
      end
      FileUtils.cp(source_path, File.join(AppConfig[:yale_accession_marc_export_path], remote_target_file))
    else
      raise "AppConfig[:yale_accession_marc_export_target] value not supported: #{AppConfig[:yale_accession_marc_export_target]}"
    end
  end

end
