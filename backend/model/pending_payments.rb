class PendingPayments

  def initialize(db, date, logger = nil)
    @db = db
    @date = date
    @logger = logger
    @payments = load_payments
  end

  def log(s)
    if @logger
      @logger.call(s)
    end
  end

  def empty?
    @payments.empty?
  end

  # Iterate pending payments yielding |accession, vendor_code, payment|
  def each
    vendor_codes_by_accession = find_vendor_codes_for_accessions(@payments.map(&:accession_id).uniq)

    @payments.each do |payment|
      if payment.voyager_fund_code.length > 10
        log("WARNING: Generated voyager_fund_code is greater than 10 characters: #{payment.voyager_fund_code} payment: #{payment}")
      end

      vendors = vendor_codes_by_accession.fetch(payment.accession_id, [])

      if vendors.length > 1
        log("ACTION REQUIRED: Payment is associated with two or more vendors and will be skipped - vendors: #{vendors.to_a}, payment: #{payment}")
      elsif vendors.length == 0
        log("ACTION REQUIRED: Payment skipped as vendor code missing: #{payment}")
      else
        payment.vendor_code = vendors.first
      end
    end

    # We'll produce one MARC record per accession/vendor/payment combo.  In the
    # interest of efficiency, batch our accession record lookups.
    @payments.group_by(&:accession_id)
      .values
      .each_slice(25) do |accession_payments|
      resolved_by_accession_id = {}

      accession_ids = accession_payments.map {|group| group.first.accession_id}
      accession_records = Accession.any_repo.filter(:id => accession_ids).all

      accession_records.group_by(&:repo_id).each do |repo_id, accessions|
        RequestContext.open(:repo_id => repo_id) do
          resolved = URIResolver.resolve_references(
            Accession.sequel_to_jsonmodel(accessions),
            ['linked_agents']
          )

          accessions.zip(resolved).each do |accession, resolved|
            resolved_by_accession_id[accession.id] = resolved
          end
        end
      end

      accession_payments.flatten.each do |payment|
        next if payment.vendor_code.nil?

        accession = JSONModel::JSONModel(:accession).new(resolved_by_accession_id.fetch(payment.accession_id))
        yield accession, payment.vendor_code, payment
      end
    end
  end

  private

  def load_payments
    date = @date

    @db[:payment]
      .join(:payment_summary, Sequel.qualify(:payment, :payment_summary_id) => Sequel.qualify(:payment_summary, :id))
      .filter{ Sequel.qualify(:payment, :payment_date) <= date}
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

  def find_vendor_codes_for_accessions(accession_ids)
    result = {}

    @db[:linked_agents_rlshp]
      .left_join(:agent_person, Sequel.qualify(:agent_person, :id) => Sequel.qualify(:linked_agents_rlshp, :agent_person_id))
      .left_join(:agent_corporate_entity, Sequel.qualify(:agent_corporate_entity, :id) => Sequel.qualify(:linked_agents_rlshp, :agent_corporate_entity_id))
      .left_join(:agent_family, Sequel.qualify(:agent_family, :id) => Sequel.qualify(:linked_agents_rlshp, :agent_family_id))
      .left_join(:agent_software, Sequel.qualify(:agent_software, :id) => Sequel.qualify(:linked_agents_rlshp, :agent_software_id))
      .filter(Sequel.|(Sequel.~(Sequel.qualify(:agent_person, :vendor_code) => nil),
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

  PaymentToProcess = Struct.new(:accession_id, :payment_id, :payment_date, :amount, :invoice_number, :fund_code, :cost_center, :spend_category, :vendor_code) do
    def voyager_fund_code
      [
        fund_code,
        cost_center.to_s[-1],
        spend_category.to_s[-3..-1]
      ].compact.join.gsub(/[^a-zA-Z0-9]/, '')
    end
  end

end
