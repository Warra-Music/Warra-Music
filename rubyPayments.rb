require 'stripe'
require 'sinatra'
require 'json'
require 'date'
require 'sinatra/cross_origin'

# Set your Stripe API key

Stripe.api_key = ENV["STRIPE_SECRET_KEY"]


# Add at the top of your Ruby file
require 'sinatra/cross_origin'

configure do
  enable :cross_origin
end

before do
  response.headers['Access-Control-Allow-Origin'] = '*'
  response.headers['Access-Control-Allow-Methods'] = 'POST, OPTIONS'
  response.headers['Access-Control-Allow-Headers'] = 'Content-Type'
end

options '*' do
  response.headers['Allow'] = 'POST, OPTIONS'
  200
end

set :public_folder, '.'

post '/create-checkout-session' do
  content_type :json

  begin
    payload = JSON.parse(request.body.read)

    booking_date = Date.parse(payload['bookingDate']) rescue Date.today
    trial_end_date = booking_date - 1
    trial_end_unix = [trial_end_date.to_time.to_i, Time.now.to_i + 60].max

    customer = Stripe::Customer.create({
      name: payload['name'],
      email: payload['email'],
      phone: payload['number']
    })

    puts "📞 Phone number received: '#{payload['number']}'"

    success_url = "#{request.base_url}/success.html?" \
      "session_id={CHECKOUT_SESSION_ID}" \
      "&customer_id=#{customer.id}" \
      "&name=#{URI.encode_www_form_component(payload['name'])}" \
      "&email=#{URI.encode_www_form_component(payload['email'])}" \
      "&instrument=#{URI.encode_www_form_component(payload['instrument'])}" \
      "&bookingDate=#{URI.encode_www_form_component(payload['bookingDate'])}" \
      "&weekday=#{URI.encode_www_form_component(payload['weekday'])}" \
      "&time=#{URI.encode_www_form_component(payload['time'])}" \
      "&method=#{URI.encode_www_form_component(payload['method'])}" \
      "&number=#{URI.encode_www_form_component(payload['number'])}" \

    session = Stripe::Checkout::Session.create({
      customer: customer.id,
      payment_method_types: ['card'],
      line_items: [{
        price: 'price_1RqYEhBbgLT6ovycotduTf5F',
        quantity: 1,
      }],
      mode: 'subscription',
      subscription_data: {
        trial_end: trial_end_unix,
      },
      success_url: success_url,
      cancel_url: "#{request.base_url}/canceled.html",
    })

    { id: session.id }.to_json

  rescue Stripe::StripeError => e
    puts "🔴 Stripe API Error: #{e.message}"
    status 500
    { error: e.message }.to_json

  rescue => e
    puts "🔴 General Error: #{e.message}"
    puts e.backtrace.join("\n")
    status 500
    { error: e.message }.to_json
  end
end

post '/customer-portal' do
  content_type :json
  
  begin
    payload = JSON.parse(request.body.read)
    customer_id = payload['customer_id']
    
    puts "Creating portal session for customer: #{customer_id}"
    
    if !customer_id || customer_id.empty?
      status 400
      return { error: "Missing customer_id parameter" }.to_json
    end
    
    # Verify the customer exists
    begin
      customer = Stripe::Customer.retrieve(customer_id)
      puts "Found customer: #{customer.id}, email: #{customer.email}"
    rescue => e
      puts "Error retrieving customer: #{e.message}"
      status 400
      return { error: "Invalid customer ID or customer not found" }.to_json
    end
    
    # Create portal session
    session = Stripe::BillingPortal::Session.create({
      customer: customer_id,
      return_url: "#{request.base_url}/account",
    })
    
    puts "Created portal session: #{session.url}"
    { url: session.url }.to_json
  rescue => e
    puts "Error creating portal session: #{e.message}"
    puts e.backtrace.join("\n")
    status 500
    { error: e.message }.to_json
  end
end

get '/get-session-info' do
  content_type :json
  
  session_id = params['session_id']
  
  begin
    session = Stripe::Checkout::Session.retrieve(session_id)
    { customer_id: session.customer }.to_json
  rescue => e
    status 404
    { error: 'Session not found' }.to_json
  end
end

get '/' do
  send_file File.join(settings.public_folder, 'check_your_details.html')
end

get '/account' do
  send_file 'account.html'
end

set :bind, '0.0.0.0'
