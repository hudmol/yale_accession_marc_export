require 'marc'
require 'tempfile'

class AccessionMARCExport
  attr_reader :file

  def initialize(accession_data, agent_vendor_code, payments, date_run)
    @file = Tempfile.new('AccessionMARCExport')
    @accession = accession_data
    @agent_vendor_code = agent_vendor_code
    @payments = payments
    @date_run = date_run

    marc_me!
  end

  def filename
    # [4-letter vendor code]+[-A][-yyyymmdd].txt
    # Example filename: BHOR-A-20200902.txt
    # FIXME
    "#{@agent_vendor_code}-A-#{@date_run.iso8601}.txt"
  end

  def finished!
    if @file
      @file.unlink
    end
  end

  private

  def marc_me!
    @payments.each_with_index do |payment, i|
      @file.write("\r\n") if i > 0

      record = MARC::Record.new()
      record.append(MARC::ControlField.new('001', @accession.uri))
      record.append(MARC::DataField.new('245', '0',  ' ', ['a', @accession.title]))
      record.append(MARC::DataField.new('980', ' ',  ' ', ['b', "%05.2f" % (payment.amount || 0.0)]))
      record.append(MARC::DataField.new('981', ' ',  ' ', ['b', AppConfig[:yale_accession_marc_export_location_code]]))
      record.append(MARC::DataField.new('981', ' ',  ' ', ['c', payment.voyager_fund_code]))
      record.append(MARC::DataField.new('982', ' ',  ' ', ['a', payment.invoice_number]))
      record.append(MARC::DataField.new('982', ' ',  ' ', ['e', @accession.identifier]))

      @file.write(MARC::Writer.encode(record))
    end

    @file.close
  end
end