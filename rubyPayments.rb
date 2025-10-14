require 'sinatra'
require 'json'
require 'date'
require 'stripe'
require 'sinatra/cross_origin'
require 'uri'
require 'net/http'

# Stripe API key (set in Render dashboard)
Stripe.api_key = ENV['STRIPE_SECRET_KEY']

configure do
  enable :cross_origin
  set :public_folder, 'public'   # Serve static files from 'public' folder
  set :bind, '0.0.0.0'
end

before do
  headers 'Access-Control-Allow-Origin' => '*',
          'Access-Control-Allow-Methods' => 'POST, OPTIONS, GET',
          'Access-Control-Allow-Headers' => 'Content-Type'
end

options '*' do
  headers 'Allow' => 'GET, POST, OPTIONS'
  200
end

# -------- Static HTML routes --------
get '/' do
  send_file File.join(settings.public_folder, 'index.html')
end

get '/currentLevel.html' do
  send_file File.join(settings.public_folder, 'currentLevel.html')
end

get '/success.html' do
  send_file File.join(settings.public_folder, 'success.html')
end

get '/canceled.html' do
  send_file File.join(settings.public_folder, 'canceled.html')
end

get '/account' do
  send_file File.join(settings.public_folder, 'account.html')
end

get '/check_your_details' do
  send_file File.join(settings.public_folder, 'check_your_details.html')
end

# -------- Stripe Checkout --------
post '/create-checkout-session' do
  content_type :json

  begin
    payload = JSON.parse(request.body.read)
    puts "🔥 Received payload: #{payload.inspect}"

    # Extract and validate required fields
    name = payload['name'] || halt(400, { error: 'Missing name' }.to_json)
    email = payload['email'] || halt(400, { error: 'Missing email' }.to_json)
    number = payload['number'] || halt(400, { error: 'Missing phone number' }.to_json)
    plan = payload['plan'] || '30min'
    method_string = payload['method'] || 'Unknown'

    puts "✅ Name: #{name}, Email: #{email}, Phone: #{number}"
    puts "✅ Plan: #{plan}, Method string: #{method_string}"

    # Determine lesson type based on method string
    lesson_type = method_string.strip == 'Zoom ID: #322 428 0987' ? 'Zoom' : 'Private'

    puts "🎯 Determined lesson type: #{lesson_type}"

    # Decide Stripe price ID based on lesson type + plan
    price_id = case [lesson_type, plan]
              when ['Private', '30min']
                'price_1S0H5ABbgLT6ovychsMStuGR'
              when ['Private', '60min']
                'price_1S0H5yBbgLT6ovyc15JWGQbt'
              when ['Zoom', '30min']
                'price_1S0H7CBbgLT6ovyckzMX7q7d'
              when ['Zoom', '60min']
                'price_1S0H87BbgLT6ovyciPBme8JL'
              else
                halt 400, { error: "Invalid combination: lesson_type=#{lesson_type}, plan=#{plan}" }.to_json
              end

    puts "💰 Selected price_id: #{price_id}"

    # Parse booking date
    booking_date = Date.parse(payload['bookingDate']) rescue Date.today
    trial_end_date = booking_date - 1
    trial_end_unix = [trial_end_date.to_time.to_i, Time.now.to_i + 60].max
    puts "📅 Booking date: #{booking_date}, Trial end (unix): #{trial_end_unix}"

    # Create Stripe customer
    customer = Stripe::Customer.create(
      name: name,
      email: email,
      phone: number
    )
    puts "🆔 Created customer: #{customer.id}"

    # Set success/cancel URLs
    base_url = "https://warramusic.com.au"
    success_url = "#{base_url}/success.html?session_id={CHECKOUT_SESSION_ID}&customer_id=#{customer.id}"
    cancel_url = "#{base_url}/canceled.html"

    # Create Stripe Checkout session
    session = Stripe::Checkout::Session.create(
      customer: customer.id,
      mode: 'subscription',
      payment_method_types: ['card'],
      line_items: [{ price: price_id, quantity: 1 }],
      subscription_data: { trial_end: trial_end_unix },
      success_url: success_url,
      cancel_url: cancel_url
    )

    puts "🚀 Checkout session created: #{session.id}"

    status 200
    { id: session.id, customer: customer.id }.to_json

  rescue Stripe::StripeError => e
    warn "Stripe API Error: #{e.class}: #{e.message}"
    status 500
    { error: e.message }.to_json
  rescue => e
    warn "General Error: #{e.class}: #{e.message}"
    status 500
    { error: e.message }.to_json
  end
end

# -------- Stripe Customer Portal --------
post '/customer-portal' do
  content_type :json
  begin
    payload = JSON.parse(request.body.read)
    customer_id = payload['customer_id'].to_s

    halt 400, { error: 'Missing customer_id parameter' }.to_json if customer_id.empty?

    Stripe::Customer.retrieve(customer_id)

    base_url = "https://warramusic.com.au"

    portal = Stripe::BillingPortal::Session.create(
      customer: customer_id,
      return_url: "#{base_url}/account"
    )

    { url: portal.url }.to_json
  rescue => e
    warn "Portal error: #{e.message}"
    status 500
    { error: e.message }.to_json
  end
end

# -------- Session info --------

post '/book-trial' do
  content_type :json

  begin
    data = JSON.parse(request.body.read)
    uri = URI('https://script.google.com/macros/s/AKfycbwrzk2aTpun5lZRwhN6wAnKBcAzY7vFBOfVE5IgZyDdr7G8Mow5c0NNIUwEZS-MVDhQ/exec')

    # POST JSON and follow redirects
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    req = Net::HTTP::Post.new(uri)
    req['Content-Type'] = 'application/json'
    req.body = data.to_json
    res = http.request(req)

    while res.is_a?(Net::HTTPRedirection)
      uri = URI(res['location'])
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      req = Net::HTTP::Post.new(uri)
      req['Content-Type'] = 'application/json'
      req.body = data.to_json
      res = http.request(req)
    end

    # Attempt JSON parse
    begin
      result = JSON.parse(res.body)
    rescue JSON::ParserError
      # If parsing fails, but HTTP code is 200, treat as success
      if res.code.to_i == 200
        result = { 'status' => 'success' }
      else
        result = { 'status' => 'error', 'message' => "GAS returned non-JSON response, HTTP #{res.code}" }
      end
    end

    status 200
    result.to_json

  rescue => e
    status 500
    { status: 'error', message: e.message }.to_json
  end
end

# -------- Startup message --------
puts "🎵 Warra Music Payments Backend is live! 🚀"
