require 'mail'
require 'stringio'
require 'set'

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
      payments_to_process =  find_payments_to_process(db, today)

      if payments_to_process.empty?
        log("No payments to process")
      else
        accession_ids = payments_to_process.map(&:accession_id).uniq
        vendors_map = find_vendor_codes_for_accessions(db, accession_ids)
        accessions_map = build_accession_data(db, accession_ids)

        payments_to_process.each do |payment|
          vendors = vendors_map.fetch(payment.accession_id, [])
          if vendors.length > 1
            log("ACTION REQUIRED: Payment is associated with two or more vendors and will be skipped - vendors: #{vendors.to_a}, payment: #{payment}")
          else
            payment.vendor_code = vendors.first
          end
        end

        payments_by_vendor = payments_to_process.group_by(&:vendor_code)

        payments_by_vendor.each do |vendor_code, payments|
          if vendor_code.nil?
            payments.each do |payment|
              log("ACTION REQUIRED: Payment skipped as vendor code missing: #{payment}")
            end

            next
          end

          log("Processing #{payments.length} payments for vendor #{vendor_code}")

          payments.each do |payment|
            if payment.voyager_fund_code.length > 10
              log("WARNING: Generated voyager_fund_code is greater than 10 characters: #{payment.voyager_fund_code} payment: #{payment}")
            end
          end

          DB.open do |db|
            marc = nil
            begin
              marc = AccessionMARCExport.new(accessions_map.fetch(payments.first.accession_id),
                                             vendor_code,
                                             payments,
                                             today)

              upload_marc_export(marc)
              mark_payments_as_processed(db, payments, today)
            ensure
              if marc
                marc.finished!
              end
            end
          end
        end
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

  PaymentToProcess = Struct.new(:accession_id, :payment_id, :payment_date, :amount, :invoice_number, :fund_code, :cost_center, :spend_category, :vendor_code) do
    def voyager_fund_code
      [
        fund_code,
        cost_center.to_s[-1],
        spend_category.to_s[-3..-1]
      ].compact.join.gsub(/[^a-zA-Z0-9]/, '')
    end
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

  def find_payments_to_process(db, today)
    db[:payment]
      .join(:payment_summary, Sequel.qualify(:payment, :payment_summary_id) => Sequel.qualify(:payment_summary, :id))
      .filter{ Sequel.qualify(:payment, :payment_date) <= today}
      .filter(Sequel.qualify(:payment, :ok_to_pay) => 1)
      .filter(Sequel.qualify(:payment, :date_paid) => nil)
      .select(Sequel.qualify(:payment_summary, :accession_id),
              Sequel.as(Sequel.qualify(:payment, :id), :payment_id),
              Sequel.qualify(:payment, :payment_date),
              Sequel.qualify(:payment, :invoice_number),
              Sequel.qualify(:payment, :fund_code_id),
              Sequel.qualify(:payment, :cost_center_id),
              Sequel.qualify(:payment_summary, :spend_category_id),
              Sequel.qualify(:payment, :amount))
      .map do |row|
      PaymentToProcess.new(row[:accession_id],
                           row[:payment_id],
                           row[:payment_date],
                           ("%.2f" % (row[:amount] || 0.0)),
                           row[:invoice_number],
                           BackendEnumSource.value_for_id('payment_fund_code', row[:fund_code_id]),
                           BackendEnumSource.value_for_id('payments_module_cost_center', row[:cost_center_id]),
                           BackendEnumSource.value_for_id('payments_module_spend_category', row[:spend_category_id]))
    end
  end

  def find_vendor_codes_for_accessions(db, accession_ids)
    result = {}

    db[:linked_agents_rlshp]
      .left_join(:agent_person, Sequel.qualify(:agent_person, :id) => Sequel.qualify(:linked_agents_rlshp, :agent_person_id))
      .left_join(:agent_corporate_entity, Sequel.qualify(:agent_corporate_entity, :id) => Sequel.qualify(:linked_agents_rlshp, :agent_corporate_entity_id))
      .left_join(:agent_family, Sequel.qualify(:agent_family, :id) => Sequel.qualify(:linked_agents_rlshp, :agent_family_id))
      .left_join(:agent_software, Sequel.qualify(:agent_software, :id) => Sequel.qualify(:linked_agents_rlshp, :agent_software_id))
      .filter(Sequel.|(
        Sequel.~(Sequel.qualify(:agent_person, :vendor_code) => nil),
        Sequel.~(Sequel.qualify(:agent_corporate_entity, :vendor_code) => nil),
        Sequel.~(Sequel.qualify(:agent_family, :vendor_code) => nil),
        Sequel.~(Sequel.qualify(:agent_software, :vendor_code) => nil),
      ))
      .filter(Sequel.qualify(:linked_agents_rlshp, :accession_id) => accession_ids)
      .filter(Sequel.qualify(:linked_agents_rlshp, :role_id) => BackendEnumSource.id_for_value('linked_agent_role', 'source'))
      .filter(Sequel.qualify(:linked_agents_rlshp, :relator_id) => BackendEnumSource.id_for_value('linked_agent_archival_record_relators', 'bsl'))
      .select(Sequel.qualify(:linked_agents_rlshp, :accession_id),
              Sequel.as(Sequel.qualify(:agent_person, :vendor_code), :agent_person_vendor_code),
              Sequel.as(Sequel.qualify(:agent_corporate_entity, :vendor_code), :agent_corporate_entity_vendor_code),
              Sequel.as(Sequel.qualify(:agent_family, :vendor_code), :agent_family_vendor_code),
              Sequel.as(Sequel.qualify(:agent_software, :vendor_code), :agent_software_vendor_code))
      .each do |row|
      vendor_code = row[:agent_person_vendor_code] || row[:agent_corporate_entity_vendor_code] || row[:agent_family_vendor_code] || row[:agent_software_vendor_code]
      next if vendor_code.nil?

      result[row[:accession_id]] ||= Set.new
      result[row[:accession_id]] << vendor_code
    end

    result
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

  AccessionData = Struct.new(:id, :title, :uri, :identifier)

  def build_accession_data(db, accession_ids)
    result = {}

    db[:accession]
      .filter(:id => accession_ids)
      .select(:id, :title, :repo_id, :identifier)
      .map do |row|
      result[row[:id]] = AccessionData.new(row[:id],
                                           row[:title],
                                           JSONModel::JSONModel(:accession).uri_for(row[:id], :repo_id => row[:repo_id]),
                                           ASUtils.json_parse(row[:identifier]).compact.join('-'))
    end

    result
  end
end