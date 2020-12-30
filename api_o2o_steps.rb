# frozen_string_literal: true

When(/^client adds file information with data:$/) do |*args|
  @is_file = true
  @payload = []
  @boundary = ENV['BOUNDARY']
  @form_data = 'Content-Disposition: form-data;'
  file = args.shift
  input_compare = %w[filepath filename type name]

  raise 'json only!' if file.class == Cucumber::MultilineArgument::DataTable

  file = APIHelper.resolve_variable(self, file, /\{\{([a-zA-Z0-9_]+)\}\}/)
  file = JSON&.parse(file)

  input_compare.each do |data|
    raise "provide #{data}!" unless file[data].is_a? String
  end

  file_bin = File.binread(File.absolute_path(file['filepath']))
  @payload.push("--#{@boundary}\r\n")
  @payload.push("#{@form_data} name=\"#{file['name']}\"; ")
  @payload.push("filename=\"#{file['filename']}\"\r\n")
  @payload.push("Content-Type: #{file['type']}\r\n\r\n#{file_bin}\r\n")
  @payload.push("--#{@boundary}--")
end

When(
  /^client sends a multipart (POST|PUT|PATCH) data to "([^"]*)" with body:$/
) do |*args|
  payload = []
  method_type = args.shift.downcase
  url = args.shift
  body = args.shift

  url = CGI.unescape(APIHelper.resolve_variable(self, url))

  unless @boundary.is_a? String
    @boundary = ENV['BOUNDARY']
    @form_data = 'Content-Disposition: form-data;'
  end

  @headers['Content-Type'] = "multipart/form-data; boundary=#{@boundary}"
  @headers['request_bukalapak_identity'] = 'api.bukalapak.com'

  raise 'json only!' if body.class == Cucumber::MultilineArgument::DataTable

  body = APIHelper.resolve_variable(self, body, /\{\{([a-zA-Z0-9_]+)\}\}/)
  body = JSON&.parse(body)

  body.each do |key, value|
    payload << "--#{@boundary}\r\n"
    payload << "#{@form_data} name=\"#{key}\"\r\n\r\n#{value}\r\n"
  end

  payload = payload.concat(@payload) if @is_file

  options = { body: payload.join, headers: @headers, timeout: @timeout }

  @response = HTTParty.send(
    method_type,
    @path + url,
    options
  )
  @response_code = @response.code
  @body = @response.body
  @response = JSON&.parse(@response.body) unless body.nil?
end

When(/^client deletes all headers( but authorization)?$/) do |auth|
  auth_backup = @headers['Authorization']

  @headers.clear
  @headers['Authorization'] = auth_backup if auth
end

Then(/^response "([^"]*)" should have following data:$/) do |*args|
  path = args.shift
  body = JSON&.parse(args.shift)

  body.each do |key, value|
    puts "assert #{key} with value #{value}"
    step "response should have \"#{path}.#{key}\" matching \"#{value}\""
  end
end

Then(/^response "([^"]*)" type should be:$/) do |*args|
  path = args.shift
  type = JSON&.parse(args.shift)

  type.each do |key, value|
    step "assert \"#{path}.#{key}\" as \"#{value}\""
  end
end

Then(/^assert "([^"]*)" as "([^"]*)"$/) do |data, type|
  case type.downcase
  when 'integer'
    step "response \"#{data}\" should be integer"
  when 'string'
    step "response \"#{data}\" should be string"
  when 'boolean'
    step "response \"#{data}\" should be boolean"
  when 'float'
    step "response \"#{data}\" should be float"
  end
end

When(/^admin changes transaction "([^"]*)" status to "([^"]*)"$/) do |id, state|
  url = '/_exclusive/general-trade/payment-transactions/'
  url = url + id + '/' + state.to_s

  step "client sends a PATCH request to \"#{url}\""
end

When(/^admin retrieves transaction data with id "([^"]*)"$/) do |trx_id|
  step 'admin retrives all transactions'
  @response['data'].each_with_index do |child, index|
    next unless child['payment_id'] == trx_id

    @response = @response['data'][index]
    break
  end
end

When(/^admin retrives all transactions$/) do
  url = '/_exclusive/general-trade/payment-transactions'

  step "client sends a GET request to \"#{url}\""
end

Then(/^agent creates OTP$/) do
  url = '/users/tfa-status'

  steps %(
    When client sends a PUT request to \"#{url}\" with body:
      """
      {
        "state": "active"
      }
      """
  )
end

Then(/^agent adds (\d+) item from warehouse id (\d+) to cart$/) do |qty, id|
  url = '/general-trade/cart-items'

  steps %(
    When client sends a POST request to \"#{url}\" with body:
      """
      {
        "quantity": #{qty},
        "warehouse_product_id": #{id}
      }
      """
      And show me the response
  )
end

Then(/^agent change (\d+) item in cart id$/) do |qty|
  url = "/general-trade/cart-items/#{@cart_id}"

  steps %(
    When client sends a PATCH request to \"#{url}\" with body:
      """
      {
        "quantity": #{qty}
      }
      """
    And show me the response
  )
end

Then(/^agent retrieves estimated points$/) do
  url = '/agent-retention/points/transactions/estimate'

  steps %(
    When client sends a verbose POST request to \"#{url}\" with body:
      """
      {
        "remote_transaction_id": #{@rem_trx_id},
        "transaction_category": "#{@type}",
        "transaction_type": "#{@type}",
        "transaction_amount": #{@trx_amount}
      }
      """
  )
end

Then(/^agent retrieves their agent profile$/) do
  url = '/agents/me'

  step "client sends a GET request to \"#{url}\""
end

Then(/^agent retrieves their agent retention point$/) do
  url = '/agent-retention/points/my-point'

  step "client sends a GET request to \"#{url}\""
end

Then(/^agent retrieves their transaction point$/) do
  url = "/agent-retention/points/transactions/#{@invoice_id}"

  # bad performance, need extra wait
  sleep 2
  step "client sends a verbose GET request to \"#{url}\""
end

Then(/^agent retrieves cart$/) do
  url = '/general-trade/cart-items'

  step "client sends a GET request to \"#{url}\""
end

Then(/^agent validates cart items$/) do
  url = '/general-trade/cart-items/validate'

  step "client sends a GET request to \"#{url}\""
end

Then(/^agent retrieves personal data$/) do
  url = '/general-trade/me'

  step "client sends a GET request to \"#{url}\""
end

When(/^agent creates transactions with different "([^"]*)" products$/) do |type|
  type = type.upcase
  @cart_id = {}
  warehouse = [ENV["#{type}_WAREHOUSE_ID_1"], ENV["#{type}_WAREHOUSE_ID_2"]]
  qty = ENV['ITEM_QUANTITY']

  step 'client logged in for APIv4 with "AGENT_USERNAME" and "AGENT_PASSWORD"'
  warehouse.each_with_index do |_child, index|
    steps %(
      When agent adds #{qty} item from warehouse id #{warehouse[index]} to cart
      Then response status should be "201"
      And show me the response
    )
  end

  steps %(
    When agent retrieves cart
    Then response status should be "200"
    And show me the response
  )
  data = @response['data']
  data.each_with_index do |_child, index|
    @cart_id[index] = data[index]['id']
  end
end

Then(/^agent retrieves address$/) do
  steps %(
    Given client logged in for APIv4 with "AGENT_USERNAME" and "AGENT_PASSWORD"
    When agent retrieves personal data
    Then response status should be "200"
    And show me the response
    And client collects "$..data.address.id" as "address_id"
  )
end

Then(/^agent sends and validates otp$/) do
  steps %(
    Given client logged in for APIv4 with "AGENT_USERNAME" and "AGENT_PASSWORD"
    And client wanted to add header:
      | Bukalapak-OTP-Key       | #{ENV['OTP_Key']}       |
      | Bukalapak-OTP-Device-ID | #{ENV['OTP_Device_ID']} |
    And show me the headers
    When agent creates OTP
    Then show me the response
    And response status should be "200"
  )

  steps %(
    Given client wanted to delete header "Bukalapak-OTP-Key"
    And client wanted to delete header "Bukalapak-OTP-Device-ID"
    When agent validates cart items
    Then response status should be "200"
  )
end

Then(/^agent creates transaction$/) do
  url = '/general-trade/payment-transactions'

  steps %(
    Given client logged in for APIv4 with "AGENT_USERNAME" and "AGENT_PASSWORD"
    And show me the headers
    When client sends a verbose POST request to \"#{url}\" with body:
      """
      {
        "address_id": #{@address_id},
        "cart_item_ids": [#{@cart_id[0]}, #{@cart_id[1]}],
        "buyer_note": "Testing only"
      }
      """
    Then response status should be "201"
    And client collects "$..data.id" as "trx_id"
    And client collects "$..data.amount" as "trx_amount"
    And client collects "$..data.remote_transaction_id" as "rem_trx_id"
  )
end

Then(/^agent retrieves estimated point$/) do
  steps %(
    Given client logged in for APIv4 with "AGENT_USERNAME" and "AGENT_PASSWORD"
    And show me the headers
    When agent retrieves estimated points
    Then response status should be "200"
    And client collects "$..data.point" as "estimated_point"
  )
  puts "|==> estimated point #{@estimated_point}"
end

Then(/^agent creates invoices$/) do
  url = '/invoices'

  steps %(
    Given client logged in for APIv4 with "AGENT_USERNAME" and "AGENT_PASSWORD"
    And show me the headers
    When client sends a verbose POST request to \"#{url}\" with body:
      """
      {
        "transactions": [
          {
            "id": #{@trx_id},
            "type": "general-trade"
          }
        ],
        "payment_type": "deposit"
      }
      """
    Then response status should be "201"
    And client collects "$..data.payment_id" as "payment_id"
    And client collects "$..data.id" as "invoice_id"
    And client collects "$..data.transactions[0].id" as "trans_id"
    And client collects "$..data.transactions[0].type" as "type"
  )
end

Then(/^agent creates wallet$/) do
  url = '/payments/' + @payment_id.to_s + '/wallet'

  steps %(
    Given client logged in for APIv4 with "AGENT_USERNAME" and "AGENT_PASSWORD"
    And show me the headers
    And client wanted to add header:
      | Bukalapak-OTP-Key       | #{ENV['OTP_Key']}       |
      | Bukalapak-OTP-Device-ID | #{ENV['OTP_Device_ID']} |
    When client sends a verbose POST request to \"#{url}\" with body:
      """
      {}
      """
    Then response status should be "200"
  )
end

Then(/^admin is successfully change transaction state to remit$/) do
  state_flow = %w[accept deliver receive remit]

  step 'client logged in for APIv4 with "O2O_ADMIN" and "O2O_ADMIN_PASSWORD"'
  # force sleep because trx state changes slowly a.k.a bad performance
  sleep 2
  state_flow.each do |state|
    steps %(
      When admin changes transaction "#{@trx_id}" status to "force-#{state}"
      Then show me the response
      And response status should be "200"
    )
  end
end

Then(/^agent retrieves points$/) do
  steps %(
    Given client logged in for APIv4 with "AGENT_USERNAME" and "AGENT_PASSWORD"
    And show me the headers
    When agent retrieves their agent retention point
    Then response status should be "200"
    And show me the response
    And client collects "$..data.accumulated_point" as "total_point"
  )
end

Then(/^agent retrieves points by transaction id$/) do
  steps %(
    Given client logged in for APIv4 with "AGENT_USERNAME" and "AGENT_PASSWORD"
    And show me the headers
    When agent retrieves their transaction point
    Then response status should be "200"
    And show me the response
    And client collects "$..data.point" as "trx_point"
  )
end

When(/^agent validates (GT|PULSA|DATA) point$/) do |*args|
  user_type = args.shift.downcase

  step 'agent validates given point'
end

When(/^agent validates (PDAM|BPJS|TOKEN|TAGIHAN) point$/) do |*args|
  user_type = args.shift.downcase

  pending
end

When(/^agent validates rokok point$/) do
  step 'agent validates given point'
  expect(@trx_point).to eq(0)
end

Then(/^agent validates given point$/) do
  step 'agent retrieves points'
  expect(@initial_point).to eq(@total_point)
  step 'agent retrieves points by transaction id'
  expect(@trx_point).to eq(@estimated_point)

  puts "|==> Transaction amount #{@trx_amount}"
  puts "|==> Initial point for this transactions is #{@initial_point}"
  puts "|==> Final point for this transactions is #{@total_point}"
  puts "|==> Trx point rewarded #{@trx_point}"
end

When(/^agent checks initital points$/) do
  step 'agent retrieves points'
  @initial_point = @total_point
end

Then(/^validate response "([^"]*)" virtual account number$/) do |bank|
  va_number = MitraDepositHelper.form_virtual_account(bank)
  step "response should have \"$.data.va_number\" matching \"#{va_number}\""
end

When(/^client "(public|non public)" create "([^"]*)" image$/) do |user, type|
  img_path = File.absolute_path('./features/support/image/tutup botol.jpg')
  base64_img = generate_base64_img(img_path)

  case user
  when 'not public'
    steps %(
    When client sends a POST request to "/me/images" with body:
    """
    {
      "type": "#{type}",
      "image": "#{base64_img}"
    }
    """
  )

  when 'public'
    steps %(
    When client sends a POST request to "/agents/me/images" with body:
    """
    {
      "type": "#{type}",
      "image": "#{base64_img}"
    }
    """
  )
  end
end

When(/^client register as new user via API$/) do
  @headers = { 'Content-Type' => 'application/json' }

  steps %(
    When client sends a POST request to "/v2/users/register.json" with body:
      """
      {
        "user": {
          "name": "#{@myname}",
          "username": "#{@user_name}",
          "email": "#{@email}",
          "password": "#{@password_confirmation}",
          "password_confirmation": "#{@password_confirmation}",
          "policy": "#{@policy}"
        },
        "source": "bukalapak",
        "facebook": {},
        "google": {}
      }
      """
  )
end

Given(/^user to agent with "([^"]*)" and "([^"]*)"$/) do |username, password|
  @username = username
  @password = password

  step 'client fetched APIv4 access token with login'
end

When(/^client wants to change agent status$/) do
  url = '/agents/ENV:AGENT_ID'

  steps %(
    When client sends a GET request to "#{url}"
  )

  @status = @response['data']['status']
  req_status = @status == 'confirmed' ? 'deactivated' : 'confirmed'

  steps %(
    When client sends a PATCH request to "#{url}/status" with body:
    """
    {
      "status": "#{req_status}"
    }
    """
  )
end

Then(/^agent status will be change$/) do
  steps %(
    When client sends a GET request to "/agents/ENV:AGENT_ID"
  )
  status_result = @response['data']['status']

  raise 'Status tidak berubah' if status_result == @status
end

When(/^accumulated point should be equal or greater than "([^"]*)"$/) do |value|
  value = value.to_i
  accumulated_point = @accumulated_point.to_i

  expect(value).to be >= accumulated_point
end

And(/^client get correct banner type value$/) do
  data = @response['data']

  data.each_with_index do |response_data, index|
    expect(response_data['banner_type'][index].to_i.between?(1, 2))
  end
end

Then(/^user get customer service "(phone|whatsapp)" number$/) do |type|
  cs_phone = '$..cs_phone_number'
  cs_whatsapp = '$..cs_whatsapp_number'

  number = type == 'phone' ? ENV['CS_MITRA_PHONE'] : ENV['CS_MITRA_WHATSAPP']
  attr = type == 'phone' ? cs_phone : cs_whatsapp

  step "response should have \"#{attr}\" matching \"#{number}\""
end

Then(/^agent retrieves cashier cart$/) do
  url = '/_exclusive/cashiers/carts?id=ENV:USER_ID'

  step "client sends a GET request to \"#{url}\""
end

When(/^agent add product to cart$/) do
  url = '/_exclusive/cashiers/carts'

  steps %(
    When agent empties the cart
    And client sends a POST request to \"#{url}\" with body:
      """
      {
        "id": ENV:USER_ID,
        "product_id": ENV:CART_PRODUCT_ID,
        "user_stock_id": ENV:CART_USER_STOCK_ID,
        "category_name": "ENV:CART_CATEGORY_NAME",
        "name": "ENV:CART_PRODUCT_NAME",
        "original_price": ENV:CART_ORIGINAL_PRICE,
        "price": 1000,
        "quantity": 1,
        "stock": ENV:CART_STOCK_AMOUNT,
        "image":
          {
            "large_url": "ENV:CART_IMG_LARGE",
            "small_url": "ENV:CART_IMG_SMALL",
            "medium_url": "ENV:CART_IMG_MEDIUM",
            "original_url": "ENV:CART_IMG_ORIGINAL"
          }
      }
      """
  )
end

When(/^agent empties the cart$/) do
  url = '/_exclusive/cashiers/carts/ENV:USER_ID'

  steps %(
    When agent retrieves cashier cart
    And client collects "$.meta.total" as "cart_item_amount"
  )

  while @cart_item_amount.to_i.positive?
    steps %(
        When client sends a DELETE request to "#{url}" with body:
        """
        {
          "cart_index": 0
        }
        """
      )
    @cart_item_amount -= 1
  end
end

When(/^agent change quantity a product from cart$/) do
  url = '/_exclusive/cashiers/carts/ENV:USER_ID'

  steps %(
    When client sends a PUT request to "#{url}" with body:
    """
    {
      "cart_index": 0,
      "product_id": ENV:CART_PRODUCT_ID,
      "user_stock_id": ENV:CART_USER_STOCK_ID,
      "category_name": "ENV:CART_CATEGORY_NAME",
      "name": "ENV:CART_PRODUCT_NAME",
      "original_price": ENV:CART_ORIGINAL_PRICE,
      "price": 1000,
      "quantity": 2,
      "stock": ENV:CART_STOCK_AMOUNT,
      "image":
        {
          "large_url": "ENV:CART_IMG_LARGE",
          "small_url": "ENV:CART_IMG_SMALL",
          "medium_url": "ENV:CART_IMG_MEDIUM",
          "original_url": "ENV:CART_IMG_ORIGINAL"
        }
    }
    """
  )
end

When(/^admin check product is "([^"]*)" on cart$/) do |is_product_id|
  url = '/_exclusive/cashiers/carts/ENV:USER_ID/status'
  id_exist = ENV['CART_PRODUCT_ID']
  id_not_exist = ENV['CART_PRODUCT_ID_NOT_EXIST']

  product_id = is_product_id == 'exist' ? id_exist : id_not_exist
  url = url + '?product_id=' + product_id
  step "client sends a verbose GET request to \"#{url}\""
end

When(/^agent check checkout amount$/) do
  url = '/_exclusive/cashiers/transactions/amounts?user_id=ENV:USER_ID'

  step "client sends a verbose GET request to \"#{url}\""
end

When(/^agent add product to be deleted on cart$/) do
  url = '/_exclusive/cashiers/carts'

  steps %(
    When client sends a POST request to \"#{url}\" with body:
      """
      {
        "id": ENV:USER_ID,
        "product_id": null,
        "user_stock_id": null,
        "category_name": "",
        "name": "Permen",
        "original_price": 0,
        "price": 500,
        "quantity": 1,
        "stock": null,
        "image": {}
      }
      """
  )
end

When(/^agent delete the product from cart$/) do
  url = '/_exclusive/cashiers/carts/ENV:USER_ID'

  steps %(
    When client sends a DELETE request to "#{url}" with body:
    """
    {
      "cart_index": ENV:CART_INDEX
    }
    """
  )
end

When(/^agent retrieves "([^"]*)" history transaction$/) do |state|
  url = '/_exclusive/cashiers/transactions?user_id=ENV:USER_ID'
  url = url + '&state=' + state

  step "client sends a verbose GET request to \"#{url}\""
end

When(/^agent get id invoiced transaction$/) do
  url = '/_exclusive/cashiers/transactions?ENV:USER_ID&state=invoiced'

  steps %(
    When client sends a verbose GET request to \"#{url}\"
    And client collects "$..data[0].id" as "id_cashier_trx"
  )
end

When(/^agent retrieves detail transaction$/) do
  url = '/_exclusive/cashiers/transactions/{id_cashier_trx}'

  steps %(
    * agent get id invoiced transaction
    * client sends a verbose GET request to \"#{url}\"
  )
end

When(/^agent mark transaction as remmited$/) do
  step 'agent get id invoiced transaction'

  url = '/_exclusive/cashiers/transactions/{id_cashier_trx}'
  step "client sends a PATCH request to \"#{url}\""
end

When(/^agent checkout transaction$/) do
  url = '/_exclusive/cashiers/transactions'

  steps %(
    When client sends a POST request to "#{url}" with body:
    """
      {
        "user_id": ENV:USER_ID,
        "payment_amount": 1000,
        "buyer_phone": "081212345678",
        "buyer_name": "Mr. Test",
        "note": "test api automation purpose"
      }
    """
  )
end

When(/^agent retrieves inventory$/) do
  url = '/_exclusive/cashiers/inventories?user_id=ENV:USER_ID'
  url += '&status=active&offset=0&limit=20&sort=name'

  step "client sends a verbose GET request to \"#{url}\""
end

When(/^agent add new product inventory$/) do
  url = '/_exclusive/cashiers/inventories'

  steps %(
    When client sends a POST request to "#{url}" with body:
    """
      {
        "product_id": ENV:INV_PRODUCT_ID,
        "barcode": "ENV:INV_BARCODE",
        "name": "ENV:INV_NAME",
        "category": ENV:INV_CATEGORY,
        "price": ENV:INV_PRICE,
        "purchase_price": ENV:INV_PURCHASE_PRICE,
        "stock": ENV:INV_STOCK,
        "min_stock": ENV:INV_MIN_STOCK,
        "status": ENV:INV_STATUS,
        "product_image": ENV:INV_PRODUCT_IMAGE,
        "product_image_id": ENV:INV_PRODUCT_IMAGE_ID
      }
    """
  )
end

When(/^agent get last id inventory$/) do
  url = '/_exclusive/cashiers/inventories?user_id=ENV:USER_ID'
  url += '&status=active&offset=0&limit=20&sort=-id'

  steps %(
    When client sends a verbose GET request to \"#{url}\"
    And client collects "$..data[0].id" as "id_last_inventory"
  )
end

When(/^agent change inventory data$/) do
  step 'agent get last id inventory'

  url = '/_exclusive/cashiers/inventories/{id_last_inventory}'

  steps %(
    When client sends a PATCH request to "#{url}" with body:
    """
      {
        "product_id": ENV:INV_PRODUCT_ID,
        "barcode": "ENV:INV_CHANGE_BARCODE",
        "name": "ENV:INV_CHANGE_NAME",
        "category": ENV:INV_CATEGORY,
        "price": ENV:INV_CHANGE_PRICE,
        "purchase_price": ENV:INV_CHANGE_PURCHASE_PRICE,
        "stock": ENV:INV_CHANGE_STOCK,
        "min_stock": ENV:INV_MIN_STOCK,
        "status": ENV:INV_STATUS,
        "product_image": ENV:INV_CHANGE_PRODUCT_IMAGE,
        "product_image_id": ENV:INV_PRODUCT_IMAGE_ID
      }
    """
  )
end

When(/^agent delete inventory data$/) do
  step 'agent get last id inventory'

  url = '/_exclusive/cashiers/inventories/{id_last_inventory}'

  step "client sends a DELETE request to \"#{url}\""
end

When(/^agent upload inventory image$/) do
  url = '/_exclusive/cashiers/inventories/images'

  img_path = File.absolute_path('./features/support/image/tutup botol.jpg')
  base64_img = generate_base64_img(img_path)

  steps %(
    When client sends a POST request to "#{url}" with body:
    """
      {
        "image_uri": "#{base64_img}"
      }
    """
  )
end

When(/^client check the availability of "([^"]*)"$/) do |key|
  value = 'phone=' + ENV['PHONE_CHECK']

  value = 'email=' + ENV['EMAIL_CHECK'] if key.eql? 'email'

  url = '/_exclusive/users/registration-availability?' + value

  steps %(
    When client sends a GET request to "#{url}"
  )
end

When(/^client request product list$/) do
  url = '/_exclusive/general-trade/products'

  step "client sends a GET request to \"#{url}\""
end

When(/^client request product detail by ID$/) do
  @product_id = ENV['PRODUCT_ID']
  url = "/_exclusive/general-trade/products/#{@product_id}"

  step "client sends a GET request to \"#{url}\""
end

Then(/^client get product detail$/) do
  steps %(
    * response status should be \"200\"
    * response should have \"$..id\" matching \"#{@product_id}\"
    * response should have \"$..name\"
    * response should have \"$..description\"
    * response should have \"$..measurement_unit\"
    * response should have \"$..category\"
    * response should have \"$..subcategory\"
    * response should have \"$..state\"
    * response should have \"$..images\"
    * response should have \"$..bundling\"
    * response should have \"$..partner_id\"
    * response should have \"$..brand\"
  )
end

When(/^client (activate|inactivate) a product$/) do |status|
  @product_id = ENV['PRODUCT_ID']
  url = "/_exclusive/general-trade/products/#{@product_id}/#{status}"

  step "client sends a GET request to \"#{url}\""
end

Then(/^product status (active|inactive)$/) do |status|
  step 'client get product detail'

  expect(@response['data']['state']) == status
end

Then(/^client get product list$/) do
  steps %(
    * response status should be \"200\"
    * response should have \"$..id\"
    * response should have \"$..name\"
    * response should have \"$..description\"
    * response should have \"$..measurement_unit\"
  )
end

When(/^client request transaction list by seller id$/) do
  @seller_id = ENV['SELLER_ID']
  ext = "offset=0&limit=20&seller_id=#{@seller_id}&sort=-id"
  url = "/_exclusive/general-trade/payment-transactions?#{ext}"

  step "client sends a GET request to \"#{url}\""
end

Then(/^client get transaction list by seller id$/) do
  steps %(
    * response status should be \"200\"
    * response should have \"$..id\" matching \"#{@seller_id}\"
    * response should have \"$..remote_transaction_id\"
    * response should have \"$..invoice_id\"
    * response should have \"$..payment_id\"
  )
end

When(/^client request download transaction for certain date$/) do
  start_date = Time.parse(ENV['START_DATE'])
  end_date = Time.parse(ENV['END_DATE'])
  # use yyyy-mm-dd format
  # maximum date range is 14 days

  seller_id = "&seller_id=#{ENV['SELLER_ID']}&sort=-id"
  date = "&start_date=#{start_date}&end_date=#{end_date}"
  url = '/_exclusive/general-trade/payment-transactions/download?offset=0'

  step "client sends a GET request to \"#{url}#{seller_id}#{date}\""
end

When(/^client request ([^"]*) detail by id$/) do |endpoint|
  @trx_id = ENV["#{endpoint&.upcase}_ID"]
  url = "/_exclusive/general-trade/#{gt_endpoint_mapping[endpoint]}/#{@trx_id}"

  step "client sends a GET request to \"#{url}\""
end

Then(/^client get transaction detail$/) do
  steps %(
    * response status should be \"200\"
    * response should have \"$..id\" matching \"#{@trx_id}\"
    * response should have \"$..remote_transaction_id\"
    * response should have \"$..invoice_id\"
    * response should have \"$..payment_id\"
    * response should have \"$..state\"
    * response should have \"$..created_at\"
    * response should have \"$..paid_at\"
    * response should have \"$..seller\"
    * response should have \"$..partner_pod_match\"
    * response should have \"$..address\"
    * response should have \"$..cart_items\"
  )
end

When(/^client request brand list$/) do
  step 'client sends a GET request to "/_exclusive/general-trade/brands"'
end

Then(/^client get brand list$/) do
  steps %(
    * response status should be \"200\"
    * response should have \"$..id\"
    * response should have \"$..state\"
  )
end

Then(/^client get brand detail information$/) do
  steps %(
    * response status should be \"200\"
    * response should have \"$..id\"
    * response should have \"$..name\"
    * response should have \"$..logo\"
    * response should have \"$..order\"
    * response should have \"$..description\"
    * response should have \"$..valid_from\"
    * response should have \"$..valid_to\"
    * response should have \"$..weight\"
    * response should have \"$..state\"
  )
end

When(/^client request category list$/) do
  step 'client sends a GET request to "/_exclusive/general-trade/categories"'
end

Then(/^client get category list$/) do
  steps %(
    * response status should be \"200\"
    * response should have \"$..id\"
    * response should have \"$..name\"
    * response should have \"$..state\"
  )
end

Then(/^client get category detail information$/) do
  steps %(
    * response status should be \"200\"
    * response should have \"$..id\"
    * response should have \"$..name\"
    * response should have \"$..parent_id\"
    * response should have \"$..has_children\"
    * response should have \"$..level_1\"
    * response should have \"$..level_2\"
    * response should have \"$..is_promo\"
    * response should have \"$..detail\"
    * response should have \"$..order\"
    * response should have \"$..state\"
    * response should have \"$..start_at\"
    * response should have \"$..slug\"
  )
end

Then(/^agent retrieves stock movement history$/) do
  url = '/_exclusive/cashiers/stock-transactions'
  url += '?user_id=ENV:USER_ID&offset=0&limit=20'

  step "client sends a verbose GET request to \"#{url}\""
end

When(/^client request address list$/) do
  step 'client sends a GET request to "/_exclusive/general-trade/addresses/1"'
end

Then(/^client get address list$/) do
  steps %(
    * response status should be \"200\"
    * response \"$..id\" should be integer
    * response \"$..name\" should be string
    * response \"$..phone\" should be string
    * response should have \"$..email\"
    * response \"$..address\" should be string
    * response \"$..province\" should be string
    * response \"$..city\" should be string
    * response \"$..district\" should be string
    * response \"$..post_code\" should be string
  )
end

When(/^agent scan barcode from "([^"]*)" product$/) do |source|
  url = '/_exclusive/cashiers/inventories/scans?barcode='

  case source
  when 'inventory'
    url += 'ENV:CASHIER_BARCODE_INVENTORY'
  when 'grosir'
    url += 'ENV:CASHIER_BARCODE_GROSIR'
  when 'other'
    url += 'ENV:CASHIER_BARCODE_OTHER'
  end

  step "client sends a GET request to \"#{url}\""
end

Then(/^agent retrieve profile$/) do
  steps %(
    When agent retrieves their agent profile
    Then response status should be "200"
    And show me the response
    And client collects "$..username" as "username"
  )
end

Then(/^agent retrieve retention profile$/) do
  steps %(
    When agent retrieves their agent retention point
    Then response status should be "200"
    And show me the response
    And client collects "$..username" as "agent_username"
  )
end

When(/^agent validate profile$/) do
  @username_env = ENV['USERNAME']

  steps %(
    * agent retrieve profile
    * agent retrieve retention profile
  )

  expect(@username).to eq(@agent_username)
  expect(@username).to eq(@username_env)
end

When(/^admin retrives all reward promo$/) do
  url = '/_exclusive/agent-retention/point-reward-promos'

  step "client sends a GET request to \"#{url}\""
end

Then(/^admin create reward promo$/) do
  url = '/_exclusive/agent-retention/point-reward-promos'

  steps %(
    When client sends a POST request to \"#{url}\" with body:
    """
    {
        "id": null,
        "start_date": "2019-09-08",
        "end_date": "2019-12-08",
        "promo_point": "1",
        "point_reward_id": 108
    }
    """
    And show me the response
    Then response status should be "201"
    And response "$..id" should be integer
    And response "$..name" should be string
    And response "$..promo_point" should be integer
    And response "$..start_date" should be string
    And response "$..end_date" should be string
  )
end

When(/^admin get price levels$/) do
  url = '/_exclusive/general-trade/price-levels'

  steps %(
    When client sends a GET request to \"#{url}\" with body:
    And show me the response
    And response status should be "OK"
  )
end

And(/^client gets correct banner user$/) do
  filepath = './features/support/csv/o2o_agenlite_banner_users_16.csv'
  csv = CSV.read(File.absolute_path(filepath))

  csv.each_with_index do |value, index|
    @response_raw[index].should eql(value), 'File csv is not match'
  end
end

And(/^client checks all banners entity type$/) do
  @response['data'].each_with_index do |_data, index|
    steps %(
      And response \"$..data[#{index}]\" type should be:
      """
      {
        "title": "String",
        "description": "String",
        "url": "String",
        "order": "Integer",
        "image_url": "String"
      }
      """
    )
  end
end

When(/^client retrieves "([^"]*)" from warehouse$/) do |feature|
  url = '/_exclusive/general-trade-warehouses/'
  path = "#{feature}?limit=20&offset=0"

  step "client sends a GET request to \"#{url}#{path}\""
end

When(/^client retrieves detail "([^"]*)" from warehouse$/) do |feature|
  url = '/_exclusive/general-trade-warehouses/'

  steps %(
    When client retrieves "#{feature}" from warehouse
    And client collects "$.data[0].id" as "id"
    And client sends a GET request to "#{url}#{feature}/{id}"
  )
end

When(/^admin create admin address$/) do
  url = '/_exclusive/general-trade/addresses'

  steps %(
    When client sends a POST request to \"#{url}\" with body:
    """
    {
      "name": "Raedi",
      "phone": "62218560000",
      "address": "ENV:ADMIN_ADDRESS_ADDRESS_1",
      "province": "ENV:ADMIN_ADDRESS_PROVINCE_1",
      "city": "ENV:ADMIN_ADDRESS_CITY_1",
      "area": "ENV:ADMIN_ADDRESS_AREA_1",
      "district": "ENV:ADMIN_ADDRESS_DISTRICT_1",
      "post_code": "ENV:ADMIN_ADDRESS_POSTAL_CODE_1"
    }
    """
  )
end

When(
  /^admin create "([^"]*)" (default )?banner with title "([^"]*)"$/
) do |type, default, title|
  @url_banner = '/_exclusive/mitra/banners'

  step 'client logged in for APIv4 with "MOTION_ADMIN" and "MOTION_PASSWORD"'
  raise 'json only!' if title.class == Cucumber::MultilineArgument::DataTable

  body = {
    "title": title.to_s,
    "type": type.to_s,
    "description": 'Will be deleted soon',
    "url": 'https://www.bukalapak.com/',
    "published_at": '2019-05-23T00:00:00.000Z',
    "stopped_at": '2020-05-30T00:00:00.000Z',
    "default": false,
    "order": 99
  }
  body[:default] = true if default

  steps %(
    * client deletes all headers but authorization
    * client prepare banner's data
    * client sends a multipart POST data to \"#{@url_banner}\" with body:
      """
        #{body.to_json}
      """
    * response status should be "OK"
    * client collects "$..id" as "id"
    * client collects "$..title" as "title"
    * client prepare banner user's data
    * response status should be "OK"
    * show me the response
  )
  # force sleep to ensure job is triggered
  sleep 2
end

When(/^client prepare banner user's data$/) do
  url = "#{@url_banner}/#{@id}/users"

  steps %(
    * client adds file information with data:
      """
      {
        "filepath": "./features/support/csv/o2o_agenlite_banner_users_16.csv",
        "filename": "o2o_agenlite_banner_users_16.csv",
        "type": "text/csv",
        "name": "file"
      }
      """
      When client sends a multipart POST data to \"#{url}\" with body:
      """
      {}
      """
  )
end

When(/^client prepare banner's data$/) do
  steps %(
    * client adds file information with data:
      """
      {
        "filepath": "./features/support/image/banner_testing.jpg",
        "filename": "banner_testing.jpg",
        "type": "image/jpg",
        "name": "image"
      }
      """
    )
end

When(/^client retrieve detail referral voucher configuration$/) do
  url = '/_exclusive/agent-referrals/voucher-configurations'

  steps %(
    When client sends a GET request to "#{url}"
    And client collects "$.data..reward" as "voucher_reward"
    And client collects "$.data..percentage" as "voucher_percentage"
    And client collects "$.data..amount" as "voucher_amount"
    And client collects "$.data..min_transaction_value" as "voucher_min_trx"
    And client collects "$.data..quota" as "voucher_quota"
    And client collects "$.data..expired_at" as "voucher_expired_date"
    And client collects "$.data..supported_products" as "voucher_supported_prod"
  )
  @voucher_percentage = @voucher_percentage.gsub('.00', '')
  @voucher_amount = @voucher_amount.gsub('.00', '')
  @voucher_min_trx = @voucher_min_trx.gsub('.00', '')
end

When(/^client update referral voucher configuration$/) do
  url = '/_exclusive/agent-referrals/voucher-configurations'

  steps %(
    When client sends a PATCH request to "#{url}" with body:
    """
    {
      "expired_at": "ENV:REFERRAL_VOUCHER_EXPIRED_DATE",
      "reward": ENV:REFERRAL_VOUCHER_REWARD,
      "min_transaction_value": ENV:REFERRAL_VOUCHER_MIN_TRANSACTION_VALUE,
      "percentage": ENV:REFERRAL_VOUCHER_PERCENTAGE,
      "amount": ENV:REFERRAL_VOUCHER_AMOUNT,
      "quota": ENV:REFERRAL_VOUCHER_QUOTA,
      "supported_products": ENV:REFERRAL_VOUCHER_SUPPORTED_PRODUCTS
    }
    """
  )
end

When(/^client update referral voucher configuration with existing data$/) do
  url = '/_exclusive/agent-referrals/voucher-configurations'

  steps %(
    When client sends a PATCH request to "#{url}" with body:
    """
    {
      "expired_at": "#{@voucher_expired_date}",
      "reward": #{@voucher_reward},
      "min_transaction_value": #{@voucher_min_trx},
      "percentage": #{@voucher_percentage},
      "amount": #{@voucher_amount},
      "quota": #{@voucher_quota},
      "supported_products": #{@voucher_supported_prod}
    }
    """
  )
end

When(/^client user "([^"]*)" (wont )?get the banner$/) do |type, action|
  user = "MOTION_USER_#{type.upcase}"
  pass = "MOTION_PASSWORD_#{type.upcase}"

  steps %(
    * client logged in for APIv4 with \"#{user}\" and \"#{pass}\"
    * client sends a GET request to "/agents/agenlite-banners"
    * response status should be "OK"
  )

  if !action
    step "response should have \"$.data[*].title\" matching \"#{@title}\""
  else
    step "response should not have \"$.data[*].title\" matching \"#{@title}\""
  end
end

When(/^admin delete created banner$/) do
  steps %(
    * client logged in for APIv4 with "MOTION_ADMIN" and "MOTION_PASSWORD"
    * client sends a DELETE request to "/_exclusive/mitra/banners/{id}"
    * response status should be "OK"
  )
end

When(/^client retrieve emelem referral toggle status$/) do
  url = '/_exclusive/info/toggle-features?feature=emelem'

  steps %(
    When client sends a GET request to "#{url}"
    And client collects "$.data..status" as "voucher_toggle_existing_status"
  )
end

When(/^client update referral voucher toggle with existing status$/) do
  url = '/_exclusive/agent-referrals/toggles'

  steps %(
    When client sends a PATCH request to "#{url}" with body:
    """
    {
      "status": "#{@voucher_toggle_existing_status}"
    }
    """
  )
end

When(/^client create lot data warehouse/) do
  url = '/_exclusive/general-trade-warehouses/lots'

  code = 'INVENTORY-' + SecureRandom.alphanumeric(5)

  steps %(
    When client sends a POST request to \"#{url}\" with body:
    """
    {
      "code": "#{code}",
      "location_type_id": ENV:LOCATION_TYPE_ID,
      "picking_available": 1,
      "state": "active",
      "warehouse_id": ENV:WAREHOUSE_ID
    }
    """
  )
end
