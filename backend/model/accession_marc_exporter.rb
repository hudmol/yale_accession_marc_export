require 'mail'
require 'stringio'
require 'set'

require_relative 'pending_payments'

class AccessionMarcExporter

  MAX_RETRIES = 10
  RETRY_WAIT = 5 * 60

  def self.run!
    MAX_RETRIES.times.each do |i|
      exporter = self.new

      begin
        exporter.run_round!
        exporter.notify!("success")

        return
      rescue
        exporter.log(80.times.map{'!'}.join)
        exporter.log("Error running round: #{$!.message}")
        exporter.log($!.backtrace.join("\n"))

        if i == MAX_RETRIES - 1
          exporter.log("\n\nTried #{MAX_RETRIES} times. Giving up for the day.")
        end

        exporter.notify!("errored")

        sleep RETRY_WAIT
      end
    end
  end

  def notify!(subject_suffix = "")
    if AppConfig.has_key?(:yale_accession_marc_export_email_delivery_method)
      @log ||= StringIO.new

      email_content = @log.string
      mail = Mail.new do
        from(AppConfig[:yale_accession_marc_export_email_from_address])
        to(AppConfig[:yale_accession_marc_export_email_to_address])
        subject("AccessionMarcExporter report - #{subject_suffix}")
        body(email_content)
      end

      mail.delivery_method(AppConfig[:yale_accession_marc_export_email_delivery_method],
                           AppConfig[:yale_accession_marc_export_email_delivery_method_settings])

      mail.deliver

      @log.truncate(0)
    end
  end

  def run_round!
    log(80.times.map{'*'}.join)
    log("Running round at #{Time.now}")
    log(80.times.map{'*'}.join)
    log("\n")

    today = Date.today

    DB.open(false) do |db|
      payments_to_process = PendingPayments.new(db, today, proc {|msg| log(msg)})
      if payments_to_process.empty?
        log("No payments to process")
        return
      end

      exports_by_vendor = {}

      payments_to_process.each do |accession, vendor_code, payment|
        log("Processing payment for vendor #{vendor_code}")

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
          rescue
            log("Error caught during process for vendor #{vendor_code} payment #{payment}: #{$!}")
            export[:failed] = $!
          end
        end
      end

      exports_by_vendor.each do |vendor_code, export|
        next if export[:failed]

        DB.open do |db|
          begin
            upload_marc_export(export[:marc])
            export[:marc].finished!
            mark_payments_as_processed(db, export[:payments], today)

            log("Processed #{export[:payments].length} #{pluralize('payment', '', 's', export[:payments].length)} for vendor #{vendor_code}")
          end
        end
      end

      if (failure = exports_by_vendor.values.find {|export| export[:failed]})
        # Throw an exception to trigger a retry for this vendor.
        raise failure[:failed]
      end
    end

    log("\n")
    log(80.times.map{'*'}.join)
    log("Finished round at #{Time.now}")
    log(80.times.map{'*'}.join)
  end

  def log(message)
    if AppConfig.has_key?(:yale_accession_marc_export_email_delivery_method)
      @log ||= StringIO.new
      @log << message
      @log << "\n"
    end

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
    if AppConfig[:yale_accession_marc_export_target].to_s == 's3'
      log("Uploading file #{marc.filename} to S3")
      @aws_uploader ||= AWSUploader.new
      @aws_uploader.upload!(marc.filename, marc.file.path)

    elsif AppConfig[:yale_accession_marc_export_target].to_s == 'sftp'
      log("Uploading file #{marc.filename} to SFTP")
      @sftp_uploader ||= SFTPUploader.new
      @sftp_uploader.upload!(marc.filename, marc.file.path)

    elsif AppConfig[:yale_accession_marc_export_target].to_s == 'local'
      log("Storing file #{marc.filename} locally at #{AppConfig[:yale_accession_marc_export_path]}")
      unless File.directory?(AppConfig[:yale_accession_marc_export_path])
        FileUtils.mkdir_p(AppConfig[:yale_accession_marc_export_path])
      end
      FileUtils.cp(marc.file.path, File.join(AppConfig[:yale_accession_marc_export_path], marc.filename))
    else
      raise "AppConfig[:yale_accession_marc_export_target] value not supported: #{AppConfig[:yale_accession_marc_export_target]}"
    end
  end

end
