require 'pp'

class AccessionMarcExporter

  def self.run!
    10.times.each do
      begin
        return new.run_round
      rescue
        Log.error('AccessionMarcExporter run_round failed:')
        Log.exception($!)

        sleep 300
      end
    end
  end

  def run_round
    Log.info(80.times.map{'*'}.join)
    Log.info("AccessionMarcExporter running round at #{Time.now}")
    Log.info(80.times.map{'*'}.join)

    today = Date.today

    DB.open(false) do |db|
      pp payments_to_process =  find_payments_to_process(db)

      # FIXME group payments by agent code -- payments_to_process.group_by{|payment| FIXME agent id}
      pp accession_ids = payments_to_process.map(&:accession_id).uniq

      # FIXME resolve agent from agent code
      agent = AgentCorporateEntity.to_jsonmodel(93)

      # Accession.sequel_to_jsonmodel(Accession.filter(:id => accession_ids).all).map{|accession| [accession.id, accession]}.to_h
      accessions_map = build_accession_data(db, accession_ids)

      # payments_to_process.each do |agent_code, payments|
      payments_to_process.each do |payment|
        DB.open do |db|
          marc = nil
          begin
            marc = AccessionMARCExport.new(accessions_map.fetch(payment.accession_id),
                                           agent,
                                           [payment],
                                           today)

            upload_marc_export(marc)
            # mark_payments_as_processed(payment)
          ensure
            if marc
              marc.finished!
            end
          end
        end
      end
    end

    Log.info(80.times.map{'*'}.join)
    Log.info("AccessionMarcExporter finished round at #{Time.now}")
    Log.info(80.times.map{'*'}.join)
  end

  private

  PaymentToProcess = Struct.new(:accession_id, :payment_date, :amount, :invoice_number, :fund_code)

  # -Payment Date is not in the future
  # -OK to pay Boolean equals True
  # -Payment Sent Date is empty
  def find_payments_to_process(db)
    db[:payment_summary]
      .join(:payment, Sequel.qualify(:payment, :payment_summary_id) => Sequel.qualify(:payment, :id))
      .filter{ Sequel.qualify(:payment, :payment_date) < Date.today}
      .select(Sequel.qualify(:payment_summary, :accession_id),
              Sequel.qualify(:payment, :payment_date),
              Sequel.qualify(:payment, :invoice_number),
              Sequel.qualify(:payment, :fund_code_id),
              Sequel.qualify(:payment, :amount))
      .map do |row|
      PaymentToProcess.new(row[:accession_id],
                           row[:payment_date],
                           row[:amount],
                           row[:invoice_number],
                           BackendEnumSource.value_for_id('payment_fund_code', row[:fund_code_id]))
    end
  end

  def upload_marc_export(marc)
    if AppConfig[:yale_accession_marc_export_target].to_s == 's3'
      Log.debug("AccessionMarcExporter uploading file #{marc.filename} to S3")
      AWSUploader.upload!(marc.filename, marc.file.path)

    elsif AppConfig[:yale_accession_marc_export_target].to_s == 'sftp'
      Log.debug("AccessionMarcExporter uploading file #{marc.filename} to SFTP")
      @sftp_uploader ||= SFTPUploader.new
      @sftp_uploader.upload!(marc.filename, marc.file.path)

    elsif AppConfig[:yale_accession_marc_export_target].to_s == 'local'
      Log.debug("AccessionMarcExporter storing file #{marc.filename} locally at #{AppConfig[:yale_accession_marc_export_path]}")
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