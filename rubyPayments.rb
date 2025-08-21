require 'sinatra'
require 'json'
require 'date'
require 'stripe'
require 'sinatra/cross_origin'
require 'uri'  # <-- IMPORTANT

Stripe.api_key = ENV['STRIPE_SECRET_KEY'] # set in Render dashboard

configure do
  enable :cross_origin
  set :public_folder, '.'
  set :bind, '0.0.0.0'
end

before do
  headers 'Access-Control-Allow-Origin' => '*',
          'Access-Control-Allow-Methods' => 'POST, OPTIONS',
          'Access-Control-Allow-Headers' => 'Content-Type'
end

options '*' do
  headers 'Allow' => 'POST, OPTIONS'
  200
end

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

    success_url =
      "#{request.base_url}/success.html?" \
      "session_id={CHECKOUT_SESSION_ID}" \
      "&customer_id=#{customer.id}" \
      "&name=#{URI.encode_www_form_component(payload['name'].to_s)}" \
      "&email=#{URI.encode_www_form_component(payload['email'].to_s)}" \
      "&instrument=#{URI.encode_www_form_component(payload['instrument'].to_s)}" \
      "&bookingDate=#{URI.encode_www_form_component(payload['bookingDate'].to_s)}" \
      "&weekday=#{URI.encode_www_form_component(payload['weekday'].to_s)}" \
      "&time=#{URI.encode_www_form_component(payload['time'].to_s)}" \
      "&method=#{URI.encode_www_form_component(payload['method'].to_s)}" \
      "&number=#{URI.encode_www_form_component(payload['number'].to_s)}"

    session = Stripe::Checkout::Session.create(
      customer: customer.id,
      mode: 'subscription',
      payment_method_types: ['card'],
      line_items: [{
        price: 'price_1RqYEhBbgLT6ovycotduTf5F', # your Stripe Price ID
        quantity: 1
      }],
      subscription_data: { trial_end: trial_end_unix },
      success_url: success_url,
      cancel_url: "#{request.base_url}/canceled.html"
    )

    status 200
    { id: session.id }.to_json

  rescue Stripe::StripeError => e
    warn "🔴 Stripe API Error: #{e.class}: #{e.message}"
    status 500
    { error: e.message }.to_json
  rescue => e
    warn "🔴 General Error: #{e.class}: #{e.message}\n#{e.backtrace&.join("\n")}"
    status 500
    { error: e.message }.to_json
  end
end

post '/customer-portal' do
  content_type :json
  begin
    payload = JSON.parse(request.body.read)
    customer_id = payload['customer_id'].to_s

    halt 400, { error: 'Missing customer_id parameter' }.to_json if customer_id.empty?

    # Validate the customer exists (will raise if not)
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

get '/'        { send_file File.join(settings.public_folder, 'check_your_details.html') }
get '/account' { send_file 'account.html' }
