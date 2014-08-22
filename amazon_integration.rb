require "sinatra"
require "endpoint_base"
require 'mws-connect'

require_all 'lib'

class AmazonIntegration < EndpointBase::Sinatra::Base
  set :logging, true

  # NOTE: Can only be used in development this will break production if left in uncommented.
  # configure :development do
  #   enable :logging, :dump_errors, :raise_errors
  #   log = File.new("tmp/sinatra.log", "a")
  #   STDOUT.reopen(log)
  #   STDERR.reopen(log)
  # end

  before do
    if @config
      @mws = Mws.connect(
        merchant: @config['merchant_id'],
        access:   @config['aws_access_key_id'],
        secret:   @config['secret_key']
      )
    end
  end

  post '/add_product' do
    begin
      code, response = submit_product_feed
    rescue => e
      log_exception(e)
      code, response = handle_error(e)
    end
    result code, response
  end

  post '/get_customers' do
    begin
      client = MWS.customer_information(
        aws_access_key_id:     @config['aws_access_key_id'],
        aws_secret_access_key: @config['secret_key'],
        marketplace_id:        @config['marketplace_id'],
        merchant_id:           @config['merchant_id']
      )
      amazon_response = client.list_customers(date_range_start: Time.parse(@config['amazon_customers_last_polling_datetime']).iso8601.to_s, date_range_type: 'LastUpdatedDate').parse

      customers = if amazon_response['CustomerList']
        collection = amazon_response['CustomerList']['Customer'].is_a?(Array) ? amazon_response['CustomerList']['Customer'] : [amazon_response['CustomerList']['Customer']]
        collection.map { |customer| Customer.new(customer) }
      else
        []
      end

      unless customers.empty?
        customers.each { |customer| add_object :customer, customer.to_message }
        # We want to set the time to be right after the last received so convert to unix stamp to increment and convert back to iso8601.
        add_parameter 'amazon_customers_last_polling_datetime', Time.at(Time.parse(customers.last.last_updated_on).to_i + 1).utc.iso8601
      end

      code     = 200
      response = if customers.size > 0
        "Successfully received #{customers.size} customer(s) from Amazon MWS."
      else
        nil
      end
    rescue => e
      code, response = handle_error(e)
    end

    result code, response
  end

  post '/get_orders' do
    begin
      # TODO remove pending
      statuses = %w(PartiallyShipped Unshipped)
      client = MWS.orders(
        aws_access_key_id:     @config['aws_access_key_id'],
        aws_secret_access_key: @config['secret_key'],
        marketplace_id:        @config['marketplace_id'],
        merchant_id:           @config['merchant_id']
      )
      amazon_response = client.list_orders(last_updated_after: Time.parse(@config['amazon_orders_last_polling_datetime']).iso8601.to_s, order_status: statuses).parse

      orders = if amazon_response['Orders']
        collection = amazon_response['Orders']['Order'].is_a?(Array) ? amazon_response['Orders']['Order'] : [amazon_response['Orders']['Order']]
        collection.map { |order| Order.new(order, client) }
      else
        []
      end

      unless orders.empty?
        orders.each { |order| add_object :order, order.to_message }
        # We want to set the time to be right after the last received so convert to unix stamp to increment and convert back to iso8601.
        add_parameter 'amazon_orders_last_polling_datetime', Time.at(Time.parse(orders.last.last_update_date).to_i + 1).utc.iso8601
      end

      code     = 200
      response = if orders.size > 0
        "Successfully received #{orders.size} order(s) from Amazon MWS."
      else
        nil
      end
    rescue => e
      code, response = handle_error(e)
    end

    result code, response
  end

  post '/set_inventory' do
    begin
      inventory_feed = @mws.feeds.inventory.update(
        Mws::Inventory(@payload['inventory']['product_id'],
          quantity: @payload['inventory']['quantity'],
          fulfillment_type: :mfn
        )
      )
      response = "Submitted SKU #{@payload['inventory']['product_id']} MWS Inventory Feed ID: #{inventory_feed.id}"
      code = 200
    rescue => e
      code, response = handle_error(e)
    end

    result code, response
  end

  post '/update_product' do
    begin
      code, response = submit_product_feed
    rescue => e
      log_exception(e)
      code, response = handle_error(e)
    end
    result code, response
  end

  post '/update_shipment' do
    begin
      feed = AmazonFeed.new(@config)
      order = Feeds::OrderFulfillment.new(@payload['shipment'], @config['merchant_id'])

      id = feed.submit(order.feed_type, order.to_xml)
      response = "Submited Feed: feed id - #{id}"
      code = 200
    rescue => e
      code, response = handle_error(e)
    end

    result code, response
  end

  # post '/feed_status' do
  #   begin
  #     raise 'TODO?'
  #     code = 200
  #   rescue => e
  #     code, response = handle_error(e)
  #   end
  #
  #   result code, response
  # end

  private

  def submit_product_feed
    mws = Mws.connect(
      merchant: @config['merchant_id'],
      access: @config['aws_access_key_id'],
      secret: @config['secret_key']
    )

    # Assign vars outside Mws::Product block as @payload can't be accessed in it.
    brand_name = @payload['product']['properties']['brand']
    sku = @payload['product']['sku']
    title = @payload['product']['name']
    desc = @payload['product']['description']
    upc_code = @payload['product']['properties']['upc_code']

    product = Mws::Product(@payload['product']['sku']) {
      brand brand_name
      description desc
      tax_code 'GEN_TAX_CODE'
      upc upc_code
      name title
    }

    product_feed = mws.feeds.products.add(product)
    # workflow.register product_feed.id do
    #   price_feed = mws.feeds.prices.add(
    #     Mws::PriceListing('2634897', 495.99)#.on_sale(29.99, Time.now, 3.months.from_now)
    #   )
    #   image_feed = mws.feeds.images.add(
    #     Mws::ImageListing('2634897', 'http://images.bestbuy.com/BestBuy_US/images/products/2634/2634897_sa.jpg', 'Main'),
    #     Mws::ImageListing('2634897', 'http://images.bestbuy.com/BestBuy_US/images/products/2634/2634897cv1a.jpg', 'PT1')
    #   )
    #   shipping_feed = mws.feeds.shipping.add(
    #     Mws::Shipping('2634897') {
    #       restricted :alaska_hawaii, :standard, :po_box
    #       adjust 4.99, :usd, :continental_us, :standard
    #       replace 11.99, :usd, :continental_us, :expedited, :street
    #     }
    #   )
    #   workflow.register price_feed.id, image_feed.id, shipping_feed.id do
    #     inventory_feed = mws.feeds.inventory.add(
    #       Mws::Inventory('2634897', quantity: 10, fulfillment_type: :mfn)
    #     )
    #     workflow.register inventory_feed.id do
    #       puts 'The workflow is complete!'
    #     end
    #     inventory_feed.id
    #   end
    #   [ price_feed.id, image_feed.id, shipping_feed.id ]
    #  end
    #   product_feed.id
    # end
    #
    # workflow.proceed

    [200, "Submitted SKU #{sku} with MWS Feed ID: #{product_feed.id}"]
  end

  def handle_error(e)
    response = if e.message =~ /403 Forbidden/
      "403 Forbidden.  Please ensure your connection credentials are correct.  If using /get_customers webhook ensure you've enabled the Customer Information API. For further help read: https://support.wombat.co/hc/en-us/articles/203066480"
    else
      [e.message, e.backtrace.to_a].flatten.join('\n\t')
    end
    [500, response]
  end

end