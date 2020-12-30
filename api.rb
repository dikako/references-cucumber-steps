autoload :Base64, 'base64'
autoload :JsonPath, 'jsonpath'

Given(/^client fetched APIv4 access token with(out)? login$/) do |condition|
  #raise EnvVariableErrors::NotFound.new('API_CLIENT_ID') unless ENV['API_CLIENT_ID']
  #raise EnvVariableErrors::NotFound.new('API_CLIENT_SECRET') unless ENV['API_CLIENT_SECRET']
  raise EnvVariableErrors::NotFound.new('APIV4_SMOKE_TEST_URL, APIV4_STAGING_URL, or APIV4_URL') unless @apiv4_url
  body = {
    'grant_type' => 'client_credentials',
    'client_id' => ENV['APIV4_CLIENT_ID'] || "cf221b85cbc3e43be6745345",
    'client_secret' =>  ENV['APIV4_CLIENT_SECRET'] || "9e92be71e4c622bcb85acba87b4c2b4250386dcee53133542caaaaa82c4a2f63"
  }

  unless condition == 'out'
    body['grant_type'] = 'password'
    body['username'] = @username
    body['password'] = @password
    body['scope'] = ENV['SCOPE'] || 'public user'
  end

  @access_token = HTTParty.post(
    accounts_oauth_token_url,
    timeout: @timeout,
    headers: {
      'User-Agent' => @user_agent,
    'Bukalapak-Identity' => 'identity-api-testing' },
    body: body
  )['access_token'].to_s

  @headers = {
    'Content-Type' => 'application/json',
    'Authorization' => "Bearer #{@access_token}",
    'Accept' => 'application/vnd.bukalapak.v4+json',
    'User-Agent' => @user_agent,
    'Bukalapak-Identity' => 'identity-api-testing'
  }
  @path = @apiv4_url
end

Given(/^client logged in for APIv(2|4)$/) do |api_version|
  step "client logged in for APIv#{api_version} with \"USERNAME\" and \"PASSWORD\""
end

Given(/^client logged in for APIv2 with "([^"]*)" and "([^"]*)"$/) do |username, password|
  raise EnvVariableErrors::NotFound.new(username) unless ENV[username]
  raise EnvVariableErrors::NotFound.new(password) unless ENV[password]
  raise EnvVariableErrors::NotFound.new('API_SMOKE_TEST_URL, API_STAGING_URL, or API_URL') unless @api_url

  get_basic_auth = lambda do |user, pass|
    {
      'Content-Type' => 'application/json',
      'Bukalapak-Identity' => 'identity-api-testing',
      'identity' => '8b092e2652cfdf87',
      'Authorization' => "Basic #{Base64.strict_encode64("#{user}:#{pass}")}",
      'User-Agent' => @user_agent
    }
  end

  @path = @api_url
  @headers = get_basic_auth.call(ENV[username], ENV[password])

  step "client sends a POST request to \"/authenticate.json\""
  @headers = get_basic_auth.call(@response['user_id'], @response['token'])
end

Given(/^client logged in for APIv4 with "([^"]*)" and "([^"]*)"$/) do |username, password|
  raise EnvVariableErrors::NotFound.new(username) unless ENV[username]
  raise EnvVariableErrors::NotFound.new(password) unless ENV[password]

  @username = ENV[username]
  @password = ENV[password]

  step 'client fetched APIv4 access token with login'
end

Given(/^client logged in for APIv4 internal endpoint$/) do
  raise EnvVariableErrors::NotFound.new('SERVICE_USERNAME') unless ENV['SERVICE_USERNAME']
  raise EnvVariableErrors::NotFound.new('SERVICE_PASSWORD') unless ENV['SERVICE_PASSWORD']

  @headers = {
    'Content-Type' => 'application/json',
    'Bukalapak-Identity' => 'identity-api-testing',
    'Authorization' => "Basic #{Base64.strict_encode64("#{ENV['SERVICE_USERNAME']}:#{ENV['SERVICE_PASSWORD']}")}",
    'User-Agent' => @user_agent
  }
end

Given(/^client logged in for partner endpoint$/) do
  auth = "#{ENV['PARTNER_USERNAME']}:#{ENV['PARTNER_PASSWORD']}"

  @headers = {
    'Content-Type' => 'application/json',
    'Bukalapak-Identity' => 'identity-api-testing',
    'Authorization' => "Basic #{Base64.strict_encode64(auth)}",
    'User-Agent' => @user_agent
  }
  @path = ENV['PARTNER_HOST']
end

Given(/^client not logged in for APIv2$/) do
  @headers = {
    'Content-Type' => 'application/json',
    'Bukalapak-Identity' => 'identity-api-testing',
    'User-Agent' => @user_agent
  }
end

Given(/^client wanted to add header:$/) do |table|
  data_table = table.rows_hash
  table = Hash.new

  data_table.each do |key, data|
    if data.include? 'ENV:'
      env = data.gsub('ENV:', '')
      table[key.to_s] = ENV[env.to_s]
    elsif data.include? '{{'
      data = data.gsub('{{', '')
      data = data.gsub('}}', '')
      table[key.to_s] = instance_variable_get('@' + data)
    else
      table[key.to_s] = data
    end
  end
  @headers.merge!(table)
end

Given(/^client wanted to delete header "([^"]*)"$/) do |variable|
  @headers.delete(variable)
end

Given(/^internal APIv4 URL "([^"]*)"$/) do |url|
  @path = ENV[url.to_s]
end

Given(Regexp.new('(?:(\d+) days? (.+) )?today\'s date is set as "([^"]+)" '\
'in format "([^"]+)"')) do |days, adj, var_name, date_format|
  time = Time.now
  if days
    op = '+'
    op = '-' if adj == 'before'
    time = time.send(op, 24 * 60 * 60 * days.to_i)
  end
  instance_variable_set("@#{var_name}", time.strftime(date_format))
end

When(/^client collects "([^"]+)"$/) do |json_path|
  step "client collects \"#{json_path}\" as \"#{json_path.gsub(/[^0-9a-zA-Z_]/, '')}\""
end

When(/^client collects "([^"]+)" as "([^"]+)"$/) do |json_path, var|
  raise 'No response returned!' if @response.nil?
  value = JsonPath.new(json_path).on(@response)
  raise "Found multiple values to assign to @#{var}" if value.size > 1

  instance_variable_set("@#{var}", value.first)
end

When(/^client logs out$/) do
  @headers.delete('Authorization')
end

When(/^client sends a (verbose )?(GET|POST|PUT|DELETE|PATCH) request to "([^"]*)"(?: with body:)?$/) do |verbose, *args|
  @path ||= @api_url

  request_type = args.shift.downcase
  path = URI.encode(APIHelper.resolve_variable(self, @path + args.shift))
  input = args.shift
  options = { headers: @headers, timeout: @timeout}

  input = input.rows_hash.to_json if input.class == Cucumber::MultilineArgument::DataTable
  options[:body] = APIHelper.resolve_variable(self, input, /\{\{([a-zA-Z0-9_]+)\}\}/) if input

  retry_until_not_error(ENV['API_MAX_RETRY']&.to_i || 1) do
    start = Time.now
    begin
      response = HTTParty.send(request_type, path, options)
      @response_raw = response unless response.nil?
      body = response.body
      @response = JSON&.parse(response.body) unless body.nil?
    rescue JSON::ParserError
      puts "can't parse to json"
    end
    @response_code = response.code
    @response_time = ((Time.now - start) * 1000).to_i
    raise if @response_code =~ /[45]\d\d/
  end

  puts "verbose key is now deprecated and should not be used" if verbose
  puts "Request: #{options.to_json}"
  puts "Response code: #{@response_code}"
  puts "Response time: #{@response_time} ms"
  puts "Response body: #{@response.to_json}"
  puts "###[#{request_type.upcase}-#{path}"
end

Then(/^response "([^"]*)" should be (integer|string|datetime|boolean|float)$/) do |json_path, datatype|
  case datatype
  when 'integer'
    integer = (JsonPath.new(json_path).on(@response).first)
    expect(integer).to be_kind_of Integer
  when 'string'
    string = (JsonPath.new(json_path).on(@response).first)
    expect(string).to be_kind_of String
  when 'datetime'
    date = (JsonPath.new(json_path).on(@response).first)
    @regex = '(?:0[1-9]|[1-2]\d|3[0-1])T(?:[0-1]\d|2[0-3]):[0-5]\d:[0-5]\dZ'
    expect(date).to match(/^\d{4}-(?:0[1-9]|1[0-2])-#{@regex}$/)
  when 'boolean'
    boolean = (JsonPath.new(json_path).on(@response).first)
    expect(boolean).to be(true).or be(false)
  when 'float'
    float = (JsonPath.new(json_path).on(@response).first)
    expect(float).to be_kind_of Float
  end
end

Then(/^response in "([^"]*)" should be:$/) do |json_path, json|
  partial = JsonPath.new(json_path).on(@response).first
  expect(partial).to eq(JSON.parse(json))
end

Then(/^response status should be "([^"]*)"$/) do |status|
  error_codes = {
    'OK' => 200,
    'Created' => 201,
    'Accepted' => 202,
    'Not Found' => 404,
    'Bad Request' => 400,
    'Unauthorized' => 401,
    'Unprocessable Entity' => 422,
    'Internal Server Error' => 500
  }
  expect(@response_code).to eq(error_codes[status] || status.to_i)
end

Then(/^response should (not)?\s?have "([^"]*)"$/) do |negative, json_path|
  results = JsonPath.new(json_path).on(@response).to_a
  expect(results).send("#{'not_' unless negative}to", be_empty)
end

Then(/^response should (not)?\s?have "([^"]*)" matching "([^"]*)"$/) do |negative, json_path, value|
  results = JsonPath.new(json_path).on(@response).to_a.map(&:to_s)
  expect(results).send("#{'not_' if negative}to", include(APIHelper.resolve_variable(self, value, /\{\{([a-zA-Z0-9_]+)\}\}/)))
end

Then(/^response should (not)?\s?have "([^"]*)" containing "([^"]*)"$/) do |negative, json_path, regex|
  results = JsonPath.new(json_path).on(@response).to_a.map(&:to_s).select { |val| val =~ Regexp.new(APIHelper.resolve_variable(self, regex, /\{\{([a-zA-Z0-9_]+)\}\}/)) }
  expect(results).send("#{'not_' unless negative}to", be_empty)
end

Then(/^response should be:$/) do |json|
  expect(@response).to eq(JSON.parse(json))
end

Then(/^response should have (\d+) "([^"]*)"$/) do |counter, json_path|
  expect(JsonPath.new(json_path).on(@response).to_a.first.count).to eq(counter.to_i)
end

Then(/^show me the headers$/) do
  puts @headers.to_json
end

Then(/^show me the response$/) do
  puts @response.to_json
end

Then(/^response time should lower than (\d+) ms$/) do |time|
  @response_time.should(be <= time.to_i)
end

When(/^user authenticate with API v2$/) do
  @auth = api_authentication(@username, @password)
end
