# frozen_string_literal: true

# rubocop:disable all
Then(/^response should have "([^"]*)" greater than "([^"]*)"$/) do |jpath, val|
  results = JsonPath.new(jpath).on(@response).to_a.map(&:to_i)
  expect(results.first).to be > val.to_i
end

Then(/^histories should have "([^"]*)" "([^"]*)"$/) do |counter, json_path|
  counter = ENV[counter].to_i
  expect(JsonPath.new(json_path).on(@response).to_a.first.count).to eq(counter)
end

Then(/^sort the "([^"]*)" to ascending$/) do |param|
  @response['data'] = @response['data'].sort_by { |v| v[param] }
end

Then(/^sort the courier name to ascending$/) do
  @response['fee_list'].sort_by! { |v| v['courier_name'] }
end

Given(/^client logged in for "([^"]*)" endpoint$/) do |type|
  get_basic_auth = lambda do |user, pass|
    {
      'Content-Type' => 'application/json',
      'Authorization' => "Basic #{Base64.strict_encode64("#{user}:#{pass}")}",
      'User-Agent' => @user_agent
    }
  end

  typ = type
  case typ
  when 'gerbata'
    @headers = get_basic_auth.call('tariff', 'tariff')
  when 'replayer'
    @headers = get_basic_auth.call('test', 'test')
  end
end

Given(/^client logged in for ninjavan replayer endpoint$/) do
  @headers = {
    'Content-Type' => 'application/json',
    'X-NINJAVAN-HMAC-SHA256' => 'qz0lTxoEvuPfhelnBVgMwx9weevD8NSiE157Ny0NrmU=',
    'Authorization' => 'Basic bG9naXN0aWM6dGVzdA=='
  }
end

When(/^client send request with tracking number "([^"]*)"$/) do |number|
  @tracking_number = number
  @lion_awb_number = ''
  if [100, 104, 200].include?(@status.to_i)
    @lion_awb_number = ENV['LION_AWB_NUMBER']
  end
end

When(/^client send request with status "([^"]*)"$/) do |status|
  @status = status
end

When(/^client send request with previous status "([^"]*)"$/) do |prev_stat|
  @prev_stat = prev_stat
end

When(/^client send request with receiver name "([^"]*)"$/) do |rec_name|
  @receiver_name = rec_name
end

When(/^client send request with sender name "([^"]*)"$/) do |send_name|
  @sender_name = send_name
end

When(/^client inject tracking status for "([^"]*)"$/) do |courier_name|
  if %w[ninjavan paxel jnt].include?(courier_name)
    datetime = @date_now + ' ' + @time_now
  elsif %w[lionparcel janio].include?(courier_name)
    datetime_gmt7 = @date_now + 'T' + @time_now + '+0700'
  else
    unixtime = Time.now.to_i
  end

  @resi_code = 0
  @summary_status = 'On Process'
  if @status.to_i == 200 || @status == 'SUCCESS'
    @resi_code = 1
    @summary_status = 'Delivered'
  end

  courier = courier_name
  replayer_url = '/_partners/' + courier + '/webhook'
  case courier
  when 'ninjavan'
    steps %(
    When client sends a POST request to \
\"#{replayer_url}\" with body:
      """
        {
          "status":"#{@status}",
          "timestamp":"#{datetime}",
          "id":"3b7327b9-54bf-417f-3104-f4e155a22308",
          "previous_status":"#{@prev_stat}",
          "tracking_id":"#{@tracking_number}",
          "comments":""
        }
      """
      )
  when 'paxel'
    steps %(
      When client sends a POST request to \
\"#{replayer_url}\" with body:
      """
        {
          "actual_price": 15000,
          "actual_weight": 2000,
          "airwaybill_code": "#{@tracking_number}",
          "driver_name": "Sandi Yudha Perdana",
          "latest_status": "#{@status}",
          "logs": {
              "address": "PCV1 Kemang Jaksel",
              "city": "Jakarta Pusat",
              "created_datetime": "#{datetime}",
              "status": "#{@status}"
          },
          "receiver_name": "#{@receiver_name}",
          "sender_name": "#{@sender_name}"
        }
      """
      )
  when 'grab'
    steps %(
      When client sends a POST request to \
\"#{replayer_url}\" with body:
      """
      {
        "deliveryID": "#{@tracking_number}",
        "timestamp": #{unixtime},
        "status": "#{@status}",
        "failedReason": "",
        "sender": {
          "name": "#{@sender_name}"
        },
        "recipient": {
          "name": "#{@receiver_name}"
        },
        "driver": {
          "name": "Johanan",
          "phone": "6288822666888",
          "photoURL": "https://somephotourl.com/sgdfb6gfd87"
        }
      }
      """
      )
  when 'jnt'
    steps %(
      When client sends a POST request to \
\"#{replayer_url}\" with body:
      """
      {
        "awb":"#{@tracking_number}",
        "detail":{
           "shipped_date":"#{datetime}",
           "services_code":"EZ",
           "services_type":"",
           "actual_amount":10000,
           "weight":1000,
           "driver":{
              "id":"1",
              "name":"Anto",
              "phone":"0812121212",
              "photo":"https://dummyimage.com/600x400/000/fff"
           }
        },
        "history":[
           {
              "date_time":"#{datetime}",
              "city_name":"JAKARTA",
              "status":"#{@prev_stat}",
              "status_code":#{@status},
              "note":"",
              "receiver":""
           }
        ]
     }
      """
      )
  when 'lionparcel'
    steps %(
      When client sends a POST request to \
\"#{replayer_url}\" with body:
      """
      {
        "airwaybill_number": "#{@lion_awb_number}",
        "ticket_number": "#{@tracking_number}",
        "courier_name": "LION PARCEL",
        "pin_code": "",
        "courier_service": "Lion Parcel REGPACK",
        "actual_shipping_fee": 0,
        "actual_weight": 1000,
        "shipment_date": "#{datetime_gmt7}",
        "shipper_name": "#{@sender_name}",
        "shipper_address": "Plaza City View",
        "receiver_name": "#{@receiver_name}",
        "receiver_address": "Plaza City View lt 1",
        "summary_status": "#{summary_status}",
        "last_status": "101",
        "last_update_at": "#{datetime_gmt7}",
        "shipment_histories": [
          {
            "position": "Jakarta Selatan",
            "status": "#{@status}",
            "time": "#{datetime_gmt7}"
          }
        ],
        "additional_data": {
          "flag": "#{@status}"
        },
        "resi_status": #{@resi_code},
        "version": "2.0"
      }
      """
        )
  else
    steps %(
        When client sends a POST request to \
\"#{replayer_url}\" with body:
        """
        {
          "airwaybill_number":"#{@tracking_number}",
          "ticket_number":"#{@tracking_number}",
          "courier_name":"JANIO",
          "courier_service":"Janio Express",
          "courier_driver":{},
          "pin_code":123456,
          "actual_shipping_fee":0,
          "actual_weight":500,
          "shipment_date":"#{datetime_gmt7}",
          "shipper_name":"#{@sender_name}",
          "shipper_address":"Kelapa Gading, Jakarta Utara, Indonesia",
          "receiver_name":"#{@receiver_name}",
          "receiver_address":"Geelang 127, Singapore",
          "summary_status":"#{@summary_status}",
          "last_status":"#{@status}",
          "last_update_at":"#{datetime_gmt7}",
          "shipment_histories":[
             {
                "position":"",
                "status":"#{@status}",
                "time":"#{datetime_gmt7}",
                "note":""
             }
          ],
          "additional_data":{
             "flag":"#{@status}"
          },
          "error_text":"",
          "resi_status":#{@resi_code},
          "version":"2.0"
       }
        """
          )
  end
end
