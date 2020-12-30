# frozen_string_literal: true

#
# general inquiry
#
Given(/^client has an available postpaid (.*) customer number$/) do |product|
  step 'client logged in for APIv4'
  step "client inquires postpaid #{product} and expect to success"
end

Given(
  /^client has (.*) partner postpaid (.*) customer number$/
) do |partner, product|
  step 'client logged in for APIv4'
  step "client inquires postpaid #{product} for #{partner} partner"
end

When(
  /^client inquires postpaid (.*) and expect to (success|fail)$/
) do |product, expectation|
  klass = Vp::Postpaid::Products.new(product.snake_case)
  pre_inquiry_data = nil

  if klass.need_pre_inquiry_data?
    step "client sends a GET request to \"#{klass.pre_inquiry_endpoint}\""
    pre_inquiry_data = @response['data']
  end

  klass.inquiry_value(@partner).each do |data|
    request_body = klass.inquiry_request_body(data, pre_inquiry_data)
    next unless request_body

    steps %(
      When client sends a POST request to "#{klass.inquiry_endpoint}" with body:
        #{request_body}
    )
    @customer_number = klass.process_inquiry_result(@response, expectation,
                                                    data[:customer_number])
    break if @customer_number
  end

  unless @customer_number
    klass.send_reminder
    skip_this_scenario
  end
end

When(/^client inquires postpaid (.*) for (.*) partner$/) do |product, partner|
  @partner = "numbers_#{partner.downcase}"
  step "client inquires postpaid #{product} and expect to success"
end

#
# partner related
#
Given(/^postpaid (.*) partner (.*) is currently active$/) do |product, partner|
  klass = Vp::Postpaid::Products.new(product.snake_case)

  step "client sends a GET request to \"#{klass.partner_list_endpoint}\""
  @active_partner = klass.active_partner(@response)
  @target_partner = klass.specific_partner(@response, partner)
  @http_method = klass.partner_change_http_method

  url = @target_partner[:url]

  steps %(
    When client sends a #{@http_method} request to "#{url}" with body:
      #{@target_partner[:body]}
  )
end

Then(/^active postpaid partner can be returned to the previous active one$/) do
  url = @active_partner[:url]

  steps %(
    When client sends a #{@http_method} request to "#{url}" with body:
      #{@active_partner[:body]}
  )
end

#
# period checker
#
Then(/^(?:postpaid electricity|telkom) periods should be strings$/) do
  periods = JsonPath.new('$.data.period').on(@response).first ||
            JsonPath.new('$.data.periods').on(@response).first
  periods.each { |period| expect(period).to be_a(String) }
end

#
# electricity
#
Given(/^client has electricity partner$/) do
  step 'client sends a GET request to ' \
       '"/_exclusive/electricities/postpaid-partners"'

  Vp::Postpaid::Products.extract_api_response(self, @response,
                                              jsonpath: '$.data[0]')
end

Then(/^postpaid electricity bills should be valid$/) do
  json_path = '$.data.bills'
  bills = JsonPath.new(json_path).on(@response).first

  step "response should have \"#{json_path}\""

  bills.each do |bill|
    next if bill.empty?

    expect(bill['bill_period']).to be_a(String)
    expect(bill['penalty_fee']).to be_an(Integer)
    expect(bill['amount']).to be_an(Integer)
  end
end

#
# bpjs
#
Given(/^client has BPJS partner$/) do
  step 'client sends a GET request to "/_exclusive/bpjs-kesehatan/partners"'

  Vp::Postpaid::Products.extract_api_response(self, @response,
                                              jsonpath: '$.data[0]')
end

Then(/^BPJS family members should be valid$/) do
  json_path = '$.data.family_members'
  family_members = JsonPath.new(json_path).on(@response).first

  step "response should have \"#{json_path}\""

  family_members.each do |member|
    next if member.empty?

    expect(member['member_number']).to be_a(String)
    expect(member['name']).to be_a(String)
    expect(member['premium']).to be_an(Integer)
    expect(member['balance']).to be_an(Integer)
  end
end

#
# pdam
#
Then(/^PDAM bills should be valid$/) do
  json_path = '$.data.bills'
  bills = JsonPath.new(json_path).on(@response).first

  step "response should have \"#{json_path}\""

  bills.each do |bill|
    next if bill.empty?

    expect(bill['bill_period']).to be_a(String)
    expect(bill['amount']).to be_an(Integer)
    expect(bill['penalty_fee']).to be_an(Integer)
    expect(bill['usage']).to be_an(Integer)
    expect(bill['cubication']).to match(/\d+-\d+/)
  end
end

#
# credit card bill
#
Given(/^a credit card bill biller is created$/) do
  endpoint = '/_exclusive/credit-card-bills/billers'

  steps %(
    When client sends a POST request to "#{endpoint}" with body:
      """
      {
        "name": "Credit Card Bill Delete Testing Biller",
        "image_url": "no url",
        "active": false
      }
      """
    And client collects "$.data.id" as "target_id"
  )
end

Given(/^a credit card bill biller partner is created$/) do
  endpoint = '/_exclusive/credit-card-bills/billers/{biller_id}/partners'

  steps %(
    Given client has credit card bill biller
    When client sends a POST request to "#{endpoint}" with body:
      """
      {
        "name": "{{partner_name}}",
        "terms_and_conditions": "No terms and condition",
        "biller_code": "{{partner_name}}123",
        "bukalapak_admin_charge": 2000,
        "partner_admin_charge": 500,
        "active": false
      }
      """
  )
end

Given(/^client has credit card bill biller$/) do
  step 'client sends a GET request to "/_exclusive/credit-card-bills/billers"'

  Vp::Postpaid::Products.extract_api_response(self, @response, 'biller')
end

Given(/^client has credit card bill partner$/) do
  step 'client sends a GET request to "/_exclusive/credit-card-bills/partners"'
  step 'client collects "$.data.names[0]" as "partner_name"'
end

When(/^client obtains valid credit card bill minimum payment$/) do
  step 'client collects "$..minimum_payment"'
  @amount = @minimum_payment.to_s == '' ? '10000' : @minimum_payment
end

Then(/^created credit card bill biller can be safely deleted$/) do
  @client.query(
    'DELETE FROM olympus_development.credit_card_biller ' \
    "WHERE id = #{@target_id}"
  )
end

Then(/^created credit card bill biller partner can be safely deleted$/) do
  @client.query(
    'DELETE FROM olympus_development.credit_card_bill_partner ' \
    "WHERE id = #{@target_id}"
  )
end

#
# cable tv
#
Given(/^client has cable TV biller$/) do
  step 'client sends a GET request to "/_exclusive/cable-tv/billers"'

  Vp::Postpaid::Products.extract_api_response(self, @response, 'biller')
end

Given(/^client has cable TV partner$/) do
  step 'client sends a GET request to "/_exclusive/cable-tv/partners"'
  step 'client collects "$.data[0].alias" as "partner_alias"'
  step 'client collects "$.data[0].name" as "partner_name"'
end

Then(/^cable TV receipt payload should be valid$/) do
  json_path = '$.data.receipt.payload'
  payload = JsonPath.new(json_path).on(@response).first

  step "response should have \"#{json_path}\""

  payload.each do |obj|
    expect(obj['label']).to be_a(String)
    expect(obj['value']).to be_a(String)
  end
end

Then(/^created cable TV biller can be safely deleted$/) do
  @client
    .query("DELETE FROM thanos_development.billers WHERE id = #{@target_id}")
end

Then(/^created cable TV biller detail can be safely deleted$/) do
  @client.query(
    "DELETE FROM thanos_development.biller_details WHERE id = #{@target_id}"
  )
end

#
# multifinance
#
Given(/^a multifinance biller is created$/) do
  endpoint = '/_exclusive/multifinance/billers'

  steps %(
    When client sends a POST request to "#{endpoint}" with body:
      """
      {
        "name": "Multifinance Delete Testing Biller",
        "image_url": "no url",
        "active": false
      }
      """
    And client collects "$.data.id" as "target_id"
  )
end

Given(/^client has multifinance biller$/) do
  step 'client sends a GET request to "/_exclusive/multifinance/billers"'

  Vp::Postpaid::Products.extract_api_response(self, @response, 'biller')
end

Given(/^client has multifinance partner$/) do
  step 'client sends a GET request to "/_exclusive/multifinance/partners"'

  Vp::Postpaid::Products.extract_api_response(self, @response, 'partner')
end

Then(/^created multifinance biller can be safely deleted$/) do
  @client
    .query("DELETE FROM rentenir_development.billers WHERE id = #{@target_id}")
end

Then(/^created multifinance biller detail can be safely deleted$/) do
  @client.query(
    "DELETE FROM rentenir_development.biller_details WHERE id = #{@target_id}"
  )
end

#
# electricity non-bill
#
Given(/^client has electricity non-bill partner$/) do
  step 'client sends a GET request to ' \
       '"/_exclusive/electricities/non-bill-partners"'

  Vp::Postpaid::Products.extract_api_response(self, @response, 'partner')
end

Then(/^created electricity non-bill partner can be safely deleted$/) do
  @client
    .query("DELETE FROM zeus_development.partners WHERE id = #{@target_id}")
end

#
# telkom
#
Given(/^client has telkom partner$/) do
  step 'client sends a GET request to "/_exclusive/telkom-postpaids/partners"'

  Vp::Postpaid::Products.extract_api_response(self, @response, 'partner')
end
