# rubocop:disable LineLength
# frozen_string_literal: true

And(/^check status flash deal$/) do
  @status_flashdeal = JsonPath.new('$..state').on(@response)[0]
  @get_product_id = JsonPath.new('$..product_id').on(@response)[0]
  step 'user choose product flash deal' if @status_flashdeal.to_s == 'current'
end

Then(/^user choose product flash deal$/) do
  @get_products_id = JsonPath.new('$..product_id').on(@response)
  @stock_each_product = JsonPath.new('$..stock').on(@response)
  count_product = @get_products_id.count
  i = 1
  is_stock_empty = true
  while i < count_product && is_stock_empty == true
    if @stock_each_product[i].to_i.positive?
      is_stock_empty = false
      @get_product_id = JsonPath.new('$..product_id').on(@response)[i]
      @get_product_sku_id = JsonPath.new('$..product_sku_id').on(@response)[i]
    else
      i += 1
    end
  end
  step 'user add product to cart' if is_stock_empty == false
end

When(/^user add product to cart$/) do
  atc_flashdeal = '"/flash_deal.json"'
  steps %(
    When client sends a POST request to #{atc_flashdeal} with body:
    """
    {
      "product_sku_id": "#{@get_product_sku_id}",
      "product_id": "#{@get_product_id}",
      "quantity": "1"
    }
    """
  )
  @status_atc = JsonPath.new('$..status').on(@response)
  @atc_valid = [false]
  @atc_valid = JsonPath.new('$..valid').on(@response) if @status_atc[0] == 'OK'
  step 'user buy and create invoices' if @atc_valid[0] == true
end

And(/^user buy and create invoices$/) do
  cart_id = @response['cart_id']
  seller = @response['cart'].first
  seller_id = seller['seller']['id']
  steps %(
  	When client sends a verbose POST request to \"/invoices.json\" with body:
    """
    {
      "payment_invoice": {
        "shipping_name": "Serge", "phone": "085172637222",
        "address": {
            "province": "DKI Jakarta", "city": "Jakarta Selatan",
            "area": "Mampang Prapatan", "address": "Jl. Mampang no 507",
            "post_code": "15116"},
        "transactions_attributes": [
            {
                "seller_id": #{seller_id}, "courier": "JNE REG"
            }]},
        "payment_method": "#{ENV['PAYMENT_METHOD']}",
        "cart_id": #{cart_id}}
    """
    Then response status should be "200"
  )
end

Then(/^client choose electricity product$/) do
  choose_electricity = '"/electricities/prepaid-transactions"'
  steps %(
    And client collects "$..data[1]..id" as "product_id"
    When client sends a POST request to #{choose_electricity} with body:
    """
      {
        "customer_number": "14203464186",
        "product_id": {{product_id}}
      }
    """
    And show me the response
  )
end

And(/^client enter promo code$/) do
  steps %(
    And client collects "$..data.id" as "transaction_id"
    When client sends a POST request to \"/invoices/check\" with body:
    """
      {
		    "transactions": [{
		    "id": {{transaction_id}},
		    "type": "electricity-prepaid"
		  }],
		  "payment_type": "#{ENV['PAYMENT_METHOD']}",
		  "voucher_code": "#{ENV['VOUCHER_CODE']}"
	    }
    """
    And show me the response
  )
end

And(/^client choose campaign today deals$/) do
  @campaign_type = JsonPath.new('$..type').on(@response)
  @campaign_url = JsonPath.new('$..url').on(@response)
  count_type = @campaign_type.count
  i = 1
  is_type_campaign = false
  while i < count_type && is_type_campaign == false
    if @campaign_type[i] == 'campaign'
      is_type_campaign = true
      @get_campaign_url = JsonPath.new('$..url').on(@response)[i]
    else
      i += 1
    end
  end
  @substring_url = @get_campaign_url.split('/')
  get_slug = '/campaigns/slug/' + @substring_url.last
  steps %(
    When client sends a GET request to \"#{get_slug}\"
    And show me the response
    Then response status should be "200"
  )
end

And(/^client should see products promo on that campaign$/) do
  @campaign_id = JsonPath.new('$..id').on(@response)
  product_limit = '/products?limit=20&offset=0'
  get_promo_products = '/campaigns/' + @campaign_id.first.to_s + product_limit
  steps %(
    When client sends a GET request to \"#{get_promo_products}\"
  )
end

And(/^check id current flash deal (v4|v2)$/) do |datatype|
  @state_flashdeal = JsonPath.new('$..state').on(@response)[0]
  case datatype
  when 'v4'
    @get_id_campaign = JsonPath.new('$..id').on(@response)[0]
    step 'user choose product id flash deal'\
    if @state_flashdeal.to_s == 'present'
  when 'v2'
    @get_product_id = JsonPath.new('$..product_id').on(@response)[0]
    step 'user choose product flash deal'
  end
end

Then(/^user choose product id flash deal$/) do
  get_campaign_by_id = '/_exclusive/flash-deals/'\
  'campaigns/' + @get_id_campaign.to_s + '/products'
  steps %(
    When client sends a GET request to \"#{get_campaign_by_id}\"
    And show me the response
    Then response status should be "200"
  )
  @get_products_id = JsonPath.new('$..data..id').on(@response)
  @stock_each_product = JsonPath.new('$..current_stock').on(@response)
  count_product = @get_products_id.count
  i = 0
  j = 0
  is_stock_empty = true
  while i < count_product && is_stock_empty == true
    if @stock_each_product[j].to_i.positive?
      is_stock_empty = false
      @get_product_id = JsonPath.new('$..id').on(@response)[i]
      j += 1
    else
      j += 1
      i += 2
    end
  end
  step 'user access product detail flash deal' if is_stock_empty == false
end

And(/^user access product detail flash deal$/) do
  get_detail_by_id = '/_exclusive/flash-deals/products/' + @get_product_id.to_s
  steps %(
    When client sends a GET request to \"#{get_detail_by_id}\"
    And show me the response
    Then response status should be "200"
  )
  step 'user add product to cart gundala'
end

When(/^user add product to cart gundala$/) do
  atc_flashdeal_gundala = '"/_exclusive/flash-deals"'
  steps %(
    When client sends a POST request to #{atc_flashdeal_gundala} with body:
    """
    {
      "product_id": #{@get_product_id},
      "quantity": 1
    }
    """
  )
end

When(/^user claims all voucherku$/) do
  user_claim_voucherku = '"/promos/coupons/claims"'
  steps %(
    When client sends a POST request to #{user_claim_voucherku} with body:
    """
    {
    }
    """
  )
end

When(/^client retrieve voucher info availability with "([^"]*)"$/) do |category|
  category_type = category
  retrieve_voucher_availability = '/promos/vouchers/availability?category='
  steps %(When client sends a GET request to \"#{retrieve_voucher_availability}#{category_type}\")
end

# rubocop:enable LineLength
