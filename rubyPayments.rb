require 'sinatra'
require 'json'
require 'date'
require 'stripe'
require 'sinatra/cross_origin'
require 'uri'

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
  send_file File.join(settings.public_folder, 'check_your_details.html')
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

# -------- Stripe Checkout --------
post '/create-checkout-session' do
  content_type :json
  begin
    payload = JSON.parse(request.body.read)

    booking_date = Date.parse(payload['bookingDate']) rescue Date.today
    trial_end_date = booking_date - 1
    trial_end_unix = [trial_end_date.to_time.to_i, Time.now.to_i + 60].max

    customer = Stripe::Customer.create(
      name:  payload['name'],
      email: payload['email'],
      phone: payload['number']
    )

    success_url = "#{request.base_url}/success.html?session_id={CHECKOUT_SESSION_ID}&customer_id=#{customer.id}"

    session = Stripe::Checkout::Session.create(
      customer: customer.id,
      mode: 'subscription',
      payment_method_types: ['card'],
      line_items: [{
        price: 'price_1RqYEhBbgLT6ovycotduTf5F',
        quantity: 1
      }],
      subscription_data: { trial_end: trial_end_unix },
      success_url: success_url,
      cancel_url: "#{request.base_url}/canceled.html"
    )

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

    portal = Stripe::BillingPortal::Session.create(
      customer: customer_id,
      return_url: "#{request.base_url}/account"
    )

    { url: portal.url }.to_json
  rescue => e
    warn "Portal error: #{e.message}"
    status 500
    { error: e.message }.to_json
  end
end

# -------- Session info --------
get '/get-session-info' do
  content_type :json
  begin
    session = Stripe::Checkout::Session.retrieve(params['session_id'])
    { customer_id: session.customer }.to_json
  rescue
    status 404
    { error: 'Session not found' }.to_json
  end
end

# -------- Startup message --------
puts "🎵 Warra Music Payments Backend is live! 🚀"
