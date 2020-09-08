require 'marc'
require 'tempfile'

class AccessionMARCExport
  attr_reader :file

  def initialize(accession_data, agent, payments, date_run)
    @file = Tempfile.new('AccessionMARCExport')
    @accession = accession_data
    @agent = agent
    @payments = payments
    @date_run = date_run

    marc_me!
  end

  def filename
    # [4-letter vendor code]+[-A][-yyyymmdd].txt
    # Example filename: BHOR-A-20200902.txt
    # FIXME
    "BHOR-A-#{@date_run.iso8601}.txt"
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
      record.append(MARC::DataField.new('981', ' ',  ' ', ['b', 'beints'])) #FIXME make configurable
      record.append(MARC::DataField.new('981', ' ',  ' ', ['c', payment.fund_code]))
      record.append(MARC::DataField.new('982', ' ',  ' ', ['a', payment.invoice_number]))
      record.append(MARC::DataField.new('982', ' ',  ' ', ['e', @accession.identifier]))

      @file.write(MARC::Writer.encode(record))
    end

    @file.close
  end
end