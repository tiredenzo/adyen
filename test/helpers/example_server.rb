require 'adyen'
require 'sinatra'

require 'helpers/configure_adyen'

class Adyen::ExampleServer < Sinatra::Base
  set :views,         File.join(File.dirname(__FILE__), 'views')
  set :public_folder, File.join(File.dirname(__FILE__), 'public')

  get '/' do
    erb :index
  end

  get '/hpp' do
   @payment = {
      :skin => :testing,
      :currency_code => 'EUR',
      :payment_amount => 4321,
      :merchant_reference => params[:merchant_reference] || 'HPP test order',
      :ship_before_date => (Date.today + 1).strftime('%F'),
      :session_validity => (Time.now.utc + 30*60).strftime('%FT%TZ'),
      :billing_address => {
        :street               => 'Alexanderplatz',
        :house_number_or_name => '0815',
        :city                 => 'Berlin',
        :postal_code          => '10119',
        :state_or_province    => 'Berlin',
        :country              => 'Germany',
      },
      :shopper => {
        :telephone_number       => '123-4512-345',
        :first_name             => 'John',
        :last_name              => 'Doe',
      }
    }

    erb :hpp
  end

  get '/hpp/result' do
    response = Adyen::Form.redirect_response(params)

    if response.authorised?
      @attributes = {
        psp_reference: response.psp_reference,
        merchant_reference: response.merchant_reference,
      }
      erb :authorized
    else
      status 400
      body response[:auth_result]
    end
  end

  get '/pay' do
    erb :pay
  end

  post '/pay' do
    api_request = Adyen::REST.client.authorise_payment_request
    api_request[:merchant_account] = 'VanBergenORG'
    api_request[:reference] = 'Test order #1'
    api_request.set_amount('EUR', 1234)
    api_request.set_encrypted_card_data(request)
    api_request.set_browser_info(request)

    api_response = Adyen::REST.client.execute_request(api_request)
    @attributes = {
      psp_reference: api_response.psp_reference
    }

    if api_response.redirect_shopper?
      @term_url   = request.url.sub(%r{/pay\z}, '/pay/3dsecure')
      @issuer_url = api_response[:issuer_url]
      @md         = api_response[:md]
      @pa_request = api_response[:pa_request]

      erb :redirect_shopper

    elsif api_response.authorised?
      erb :authorized

    else
      status 400
      body api_response[:refusal_reason]
    end
  end

  post '/pay/3dsecure' do
    api_request = Adyen::REST.client.authorise_payment_3dsecure_request
    api_request[:merchant_account] = 'VanBergenORG'
    api_request.set_browser_info(request)
    api_request.set_3d_secure_parameters(request)

    api_response = Adyen::REST.client.execute_request(api_request)

    @attributes = {
      psp_reference: api_response.psp_reference,
      auth_code: api_response[:auth_code],
    }

    erb :authorized
  end
end
