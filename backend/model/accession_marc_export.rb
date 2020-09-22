require 'marc'
require 'tempfile'

class AccessionMARCExport
  attr_reader :file

  def initialize(vendor_code, date_run)
    @vendor_code = vendor_code
    @date_run = date_run
    @file = Tempfile.new('AccessionMARCExport')
  end

  def add_payment(accession, payment)
    record = MARC::Record.new()
    record.append(MARC::ControlField.new('001', accession.uri))

    # Multiple date records are merged together based on their respective types
    # (single & inclusive into subfield $f, bulk into subfield $g).  Title goes in
    # $a as usual.
    Array(accession.dates).reduce({'f' => [], 'g' => []}) {|subfields, date|
      if ['single', 'inclusive'].include?(date['date_type'])
        subfields.merge('f' => (subfields['f'] + [extract_date(date)]))
      else
        subfields.merge('g' => (subfields['g'] + [extract_date(date)]))
      end
    }.tap do |date_subfields|
      title_field = MARC::DataField.new('245', '0', ' ', ['a', accession.display_string])
      unless date_subfields['f'].empty?
        title_field.append(MARC::Subfield.new('f', date_subfields['f'].join(', ')))
      end

      unless date_subfields['g'].empty?
        title_field.append(MARC::Subfield.new('g', "(bulk: %s)." % [date_subfields['g'].join(', ')]))
      end

      record.append(title_field)
    end

    record.append(MARC::DataField.new('980', ' ',  ' ', ['b', payment.amount]))
    record.append(MARC::DataField.new('981', ' ',  ' ', ['b', AppConfig[:yale_accession_marc_export_location_code]]))
    record.append(MARC::DataField.new('981', ' ',  ' ', ['c', payment.voyager_fund_code]))
    record.append(MARC::DataField.new('982', ' ',  ' ', ['a', payment.invoice_number]))
    record.append(MARC::DataField.new('982', ' ',  ' ', ['e', [accession.id_0, accession.id_1, accession.id_2, accession.id_3].compact.join('-')]))

    Array(accession.extents).each do |extent|
      record.append(MARC::DataField.new('300', ' ', ' ',
                                        ['a', extent['number']],
                                        ['f',
                                         [I18n.t("enumerations.extent_extent_type.#{extent['extent_type']}",
                                                 nil),
                                          [extent['container_summary']].compact.map {|s|
                                            # Wrap container summary with parens unless it's already wrapped.
                                            s = s.strip
                                            if s =~ /\A\(.*\)$/
                                              s
                                            else
                                              "(#{s})"
                                            end
                                          }.first
                                         ].compact.join(' '),
                                        ]))
    end

    if (s = accession.access_restrictions_note.to_s.strip) && !s.empty?
      record.append(MARC::DataField.new('506', ' ', ' ', ['a', s]))
    end

    if (s = accession.content_description.to_s.strip) && !s.empty?
      record.append(MARC::DataField.new('520', ' ', ' ', ['a', s]))
    end

    if (s = accession.provenance.to_s.strip) && !s.empty?
      record.append(MARC::DataField.new('561', ' ', ' ', ['a', s]))
    end

    # For linked agents, we want the same export rules as the standard ArchivesSpace
    # MARC export.
    aspace_marc = MARCModel.from_aspace_object(nil, :include_unpublished => true)
    aspace_marc.apply_map(JSONModel::JSONModel(:accession).new(accession), :linked_agents => :handle_agents)
    aspace_marc.datafields.each do |datafield|
      record.append(MARC::DataField.new(datafield.tag.to_s,
                                        (datafield.ind1 || ' '),
                                        (datafield.ind2 || ' '),
                                        *(datafield.subfields.map {|subfield|
                                            [subfield.code.to_s, subfield.text.to_s]
                                          })))
    end

    @file.write(MARC::Writer.encode(record))
    @file.flush
  end

  def filename
    "#{@vendor_code}-A-#{@date_run.iso8601}.txt"
  end

  def finished!
    if @file
      @file.close
      @file.unlink
    end
  end

  private

  def extract_date(date)
    if date['expression'].to_s.strip.empty?
      [date['begin'], date['end']].compact.join(' - ')
    else
      date['expression'].strip
    end
  end

end
