require 'sinatra'
require 'json'
require 'stripe'
require 'sinatra/cross_origin'

# Enable CORS (so your frontend can call this API)
configure do
  enable :cross_origin
end

# Set your Stripe secret key (from Render environment variables)
Stripe.api_key = ENV['STRIPE_SECRET_KEY']

# Allow POST from frontend
before do
  content_type :json
end

# Root route (optional)
get '/' do
  "Warra Music Payments Backend is live!"
end

# Create Stripe Checkout Session
post '/create-checkout-session' do
  request.body.rewind
  data = JSON.parse(request.body.read)

  # Extract fields from frontend
  instrument    = data['instrument'] || 'Not selected'
  level         = data['level'] || 'Not selected'
  name          = data['name'] || 'Not provided'
  email         = data['email'] || 'Not provided'
  number        = data['number'] || 'Not provided'
  bookingDate   = data['bookingDate'] || 'Not provided'
  time          = data['time'] || 'Not selected'
  weekday       = data['weekday'] || 'Not selected'
  method        = data['method'] || 'Not selected'

  begin
    # Create Stripe customer
    customer = Stripe::Customer.create(
      name: name,
      email: email,
      phone: number,
      metadata: {
        instrument: instrument,
        level: level,
        bookingDate: bookingDate,
        time: time,
        weekday: weekday,
        method: method
      }
    )

    # Create subscription session
    session = Stripe::Checkout::Session.create(
      customer: customer.id,
      payment_method_types: ['card'],
      mode: 'subscription',
      line_items: [{
        price_data: {
          currency: 'aud',
          product_data: {
            name: "30 Minute Music Lessons",
            description: "Weekly music lessons with Warra Music"
          },
          recurring: { interval: 'week' },
          unit_amount: 4000  # $40 in cents
        },
        quantity: 1
      }],
      success_url: 'https://warramusic.com.au/success.html?session_id={CHECKOUT_SESSION_ID}&customer_id={CUSTOMER_ID}',
      cancel_url: 'https://warramusic.com.au/cancel.html'
    )

    # Return session info to frontend
    { id: session.id, customer: customer.id }.to_json

  rescue Stripe::StripeError => e
    status 400
    { error: e.message }.to_json
  end
end
