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

    # UTF-8, baby
    record.leader[9] = 'a'

    four_part_id = [accession.id_0, accession.id_1, accession.id_2, accession.id_3].compact.join('-')

    # Decided we don't need this for now.
    #
    # record.append(MARC::ControlField.new('001', "%s-%s" % [four_part_id, payment.payment_id]))

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
      title_field = MARC::DataField.new('245', '0', '0', ['a', accession.display_string])
      unless date_subfields['f'].empty?
        title_field.append(MARC::Subfield.new('f', date_subfields['f'].join(', ')))
      end

      unless date_subfields['g'].empty?
        title_field.append(MARC::Subfield.new('g', "(bulk: %s)." % [date_subfields['g'].join(', ')]))
      end

      record.append(title_field)
    end

    record.append(MARC::DataField.new('980', ' ',  ' ', ['b', payment.amount]))

    MARC::DataField.new('981', ' ',  ' ').tap do |df|
      df.append(MARC::Subfield.new('b', AppConfig[:yale_accession_marc_export_location_code]))
      df.append(MARC::Subfield.new('c', payment.voyager_fund_code.strip)) unless payment.voyager_fund_code.to_s.strip.empty?
      record.append(df)
    end

    MARC::DataField.new('982', ' ',  ' ').tap do |df|
      df.append(MARC::Subfield.new('a', payment.invoice_number.strip)) unless payment.invoice_number.to_s.strip.empty?
      df.append(MARC::Subfield.new('e', four_part_id))
      record.append(df)
    end

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
    if accession.linked_agents
      accession.linked_agents.reject! {|agent| agent['role'] != 'creator'}

      unless accession.linked_agents.empty?
        aspace_marc = MARCModel.from_aspace_object(nil, :include_unpublished => true)
        aspace_marc.apply_map(accession, :linked_agents => :handle_agents)
        aspace_marc.datafields.each do |datafield|
          record.append(MARC::DataField.new(datafield.tag.to_s,
                                            (datafield.ind1 || ' '),
                                            (datafield.ind2 || ' '),
                                            *(datafield.subfields.map {|subfield|
                                                [subfield.code.to_s, subfield.text.to_s]
                                              })))
        end
      end
    end

    record.fields.sort_by!(&:tag)

    @file.write(MARC::Writer.encode(record))
    @file.flush
  end

  def filename
    extension = AppConfig.has_key?(:yale_accession_marc_export_file_extension) ?
                  AppConfig[:yale_accession_marc_export_file_extension] :
                  'txt'

    "#{@vendor_code}-A-#{@date_run.iso8601}.#{extension}"
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
