require 'sinatra'
require 'json'
require 'date'
require 'stripe'
require 'sinatra/cross_origin'

Stripe.api_key = ENV['STRIPE_SECRET_KEY']

configure do
  enable :cross_origin
  set :public_folder, 'public'
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

# Static routes
get '/' do send_file File.join(settings.public_folder, 'index.html') end
get '/check_your_details' do send_file File.join(settings.public_folder, 'check_your_details.html') end
get '/success.html' do send_file File.join(settings.public_folder, 'success.html') end
get '/canceled.html' do send_file File.join(settings.public_folder, 'canceled.html') end
get '/account' do send_file File.join(settings.public_folder, 'account.html') end

# Stripe Checkout
post '/create-checkout-session' do
  content_type :json
  begin
    payload = JSON.parse(request.body.read)

    booking_date = Date.parse(payload['bookingDate']) rescue Date.today
    trial_end_unix = [(booking_date - 1).to_time.to_i, Time.now.to_i + 60].max

    # Normalize plan and method
    plan = payload['plan']&.strip&.downcase || '30min'    # 30min / 60min
    method = payload['method']&.strip&.capitalize || 'Private' # Private / Zoom

    # Map to Stripe price ID
    price_id = case [method, plan]
               when ['Private', '30min'] then 'price_1RqYEhBbgLT6ovycotduTf5F'
               when ['Private', '60min'] then 'price_1RyvsoBbgLT6ovycfOwrQurL'
               when ['Zoom', '30min'] then 'price_1RzdaJBbgLT6ovycE5wFU9gM'
               when ['Zoom', '60min'] then 'price_1RzdcdBbgLT6ovycUdkE2XiH'
               else
                 halt 400, { error: "Invalid plan or method: #{method}/#{plan}" }.to_json
               end

    puts "Payload: #{payload.inspect}"
    puts "Using plan=#{plan}, method=#{method}, price_id=#{price_id}"

    customer = Stripe::Customer.create(
      name:  payload['name'],
      email: payload['email'],
      phone: payload['number']
    )

    base_url = "https://warramusic.com.au"

    session = Stripe::Checkout::Session.create(
      customer: customer.id,
      mode: 'subscription',
      payment_method_types: ['card'],
      line_items: [{ price: price_id, quantity: 1 }],
      subscription_data: { trial_end: trial_end_unix },
      success_url: "#{base_url}/success.html?session_id={CHECKOUT_SESSION_ID}&customer_id=#{customer.id}",
      cancel_url: "#{base_url}/canceled.html"
    )

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

# Stripe portal
post '/customer-portal' do
  content_type :json
  payload = JSON.parse(request.body.read)
  customer_id = payload['customer_id'].to_s
  halt 400, { error: 'Missing customer_id parameter' }.to_json if customer_id.empty?

  portal = Stripe::BillingPortal::Session.create(
    customer: customer_id,
    return_url: "https://warramusic.com.au/account"
  )
  { url: portal.url }.to_json
end

puts "🎵 Warra Music Payments Backend is live! 🚀"
